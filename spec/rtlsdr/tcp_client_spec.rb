# frozen_string_literal: true

require "spec_helper"

RSpec.describe RTLSDR::TcpClient do
  let(:mock_socket) { instance_double(Socket) }
  let(:host) { "192.168.1.100" }
  let(:port) { 1234 }

  # rtl_tcp header: "RTL0" + tuner_type(4) + gain_count(4)
  let(:valid_header) { "RTL0" + [5].pack("N") + [29].pack("N") }

  before do
    allow(Socket).to receive(:tcp).and_return(mock_socket)
    allow(mock_socket).to receive(:setsockopt)
    allow(mock_socket).to receive(:read).with(12).and_return(valid_header)
    allow(mock_socket).to receive(:write)
    allow(mock_socket).to receive(:closed?).and_return(false)
    allow(mock_socket).to receive(:close)
  end

  describe "#initialize" do
    it "connects to the server" do
      expect(Socket).to receive(:tcp).with(host, port, connect_timeout: 10).and_return(mock_socket)
      described_class.new(host, port)
    end

    it "reads and parses the header" do
      client = described_class.new(host, port)
      expect(client.tuner_type).to eq(5)
      expect(client.gain_count).to eq(29)
    end

    it "raises ConnectionError on invalid header" do
      allow(mock_socket).to receive(:read).with(12).and_return("BADH" + "\x00" * 8)
      expect { described_class.new(host, port) }.to raise_error(RTLSDR::ConnectionError, /Invalid rtl_tcp header/)
    end

    it "raises ConnectionError when connection refused" do
      allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
      expect { described_class.new(host, port) }.to raise_error(RTLSDR::ConnectionError, /Connection refused/)
    end

    it "raises ConnectionError when host unreachable" do
      allow(Socket).to receive(:tcp).and_raise(Errno::EHOSTUNREACH.new("No route to host"))
      expect { described_class.new(host, port) }.to raise_error(RTLSDR::ConnectionError, /Cannot reach/)
    end
  end

  describe "#open? and #closed?" do
    let(:client) { described_class.new(host, port) }

    it "returns true for open? when connected" do
      expect(client.open?).to be true
    end

    it "returns false for closed? when connected" do
      expect(client.closed?).to be false
    end

    it "returns false for open? after close" do
      client.close
      expect(client.open?).to be false
    end
  end

  describe "#close" do
    let(:client) { described_class.new(host, port) }

    it "closes the socket" do
      expect(mock_socket).to receive(:close)
      client.close
    end

    it "is safe to call multiple times" do
      client.close
      expect { client.close }.not_to raise_error
    end
  end

  describe "#name" do
    let(:client) { described_class.new(host, port) }

    it "returns rtl_tcp URL format" do
      expect(client.name).to eq("rtl_tcp://#{host}:#{port}")
    end
  end

  describe "#tuner_name" do
    let(:client) { described_class.new(host, port) }

    it "returns correct tuner name for R820T (type 5)" do
      expect(client.tuner_name).to eq("Rafael Micro R820T")
    end
  end

  describe "frequency control" do
    let(:client) { described_class.new(host, port) }

    it "sends frequency command" do
      freq = 100_000_000
      expect(mock_socket).to receive(:write).with([0x01, freq].pack("CN"))
      client.center_freq = freq
      expect(client.center_freq).to eq(freq)
    end

    it "aliases frequency to center_freq" do
      expect(client).to respond_to(:frequency)
      expect(client).to respond_to(:frequency=)
    end
  end

  describe "sample rate control" do
    let(:client) { described_class.new(host, port) }

    it "sends sample rate command" do
      rate = 2_048_000
      expect(mock_socket).to receive(:write).with([0x02, rate].pack("CN"))
      client.sample_rate = rate
      expect(client.sample_rate).to eq(rate)
    end
  end

  describe "gain control" do
    let(:client) { described_class.new(host, port) }

    it "sends gain mode command for manual" do
      expect(mock_socket).to receive(:write).with([0x03, 1].pack("CN"))
      client.manual_gain_mode!
    end

    it "sends gain mode command for auto" do
      expect(mock_socket).to receive(:write).with([0x03, 0].pack("CN"))
      client.auto_gain_mode!
    end

    it "sends gain command" do
      gain = 400
      expect(mock_socket).to receive(:write).with([0x04, gain].pack("CN"))
      client.tuner_gain = gain
      expect(client.tuner_gain).to eq(gain)
    end

    it "returns common R820T gain values" do
      gains = client.tuner_gains
      expect(gains).to be_an(Array)
      expect(gains).to include(496) # max R820T gain
    end
  end

  describe "#configure" do
    let(:client) { described_class.new(host, port) }

    it "sets frequency, sample rate, and gain" do
      expect(mock_socket).to receive(:write).with([0x01, 100_000_000].pack("CN"))
      expect(mock_socket).to receive(:write).with([0x02, 2_048_000].pack("CN"))
      expect(mock_socket).to receive(:write).with([0x03, 1].pack("CN")) # manual mode
      expect(mock_socket).to receive(:write).with([0x04, 400].pack("CN"))

      client.configure(frequency: 100_000_000, sample_rate: 2_048_000, gain: 400)
    end

    it "returns self for chaining" do
      result = client.configure(frequency: 100_000_000)
      expect(result).to eq(client)
    end
  end

  describe "#read_sync" do
    let(:client) { described_class.new(host, port) }
    let(:sample_data) { ([128, 130] * 512).pack("C*") }

    before do
      allow(mock_socket).to receive(:read).with(1024).and_return(sample_data)
    end

    it "reads raw bytes from socket" do
      data = client.read_sync(1024)
      expect(data).to be_an(Array)
      expect(data.length).to eq(1024)
    end

    it "raises ConnectionError when not connected" do
      client.close
      expect { client.read_sync(1024) }.to raise_error(RTLSDR::ConnectionError, /Not connected/)
    end

    it "raises ConnectionError when server closes connection" do
      allow(mock_socket).to receive(:read).with(1024).and_return(nil)
      expect { client.read_sync(1024) }.to raise_error(RTLSDR::ConnectionError, /closed by server/)
    end
  end

  describe "#read_samples" do
    let(:client) { described_class.new(host, port) }
    # IQ data: I=128 (0), Q=130 (+0.016), repeated
    let(:sample_data) { ([128, 130] * 512).pack("C*") }

    before do
      allow(mock_socket).to receive(:read).with(1024).and_return(sample_data)
    end

    it "returns complex samples" do
      samples = client.read_samples(512)
      expect(samples).to be_an(Array)
      expect(samples.length).to eq(512)
      expect(samples.first).to be_a(Complex)
    end

    it "converts IQ bytes to normalized range" do
      samples = client.read_samples(512)
      sample = samples.first
      expect(sample.real).to eq(0.0)
      expect(sample.imag).to be_within(0.01).of(0.016)
    end
  end

  describe "other commands" do
    let(:client) { described_class.new(host, port) }

    it "sends freq correction command" do
      expect(mock_socket).to receive(:write).with([0x05, 15].pack("CN"))
      client.freq_correction = 15
    end

    it "sends AGC mode command" do
      expect(mock_socket).to receive(:write).with([0x08, 1].pack("CN"))
      client.agc_mode = true
    end

    it "sends direct sampling command" do
      expect(mock_socket).to receive(:write).with([0x09, 1].pack("CN"))
      client.direct_sampling = 1
    end

    it "sends offset tuning command" do
      expect(mock_socket).to receive(:write).with([0x0a, 1].pack("CN"))
      client.offset_tuning = true
    end

    it "sends bias tee command" do
      expect(mock_socket).to receive(:write).with([0x0e, 1].pack("CN"))
      client.bias_tee = true
    end
  end

  describe "EEPROM operations" do
    let(:client) { described_class.new(host, port) }

    it "raises error for read_eeprom" do
      expect { client.read_eeprom(0, 256) }.to raise_error(RTLSDR::OperationFailedError, /not supported via TCP/)
    end

    it "raises error for write_eeprom" do
      expect { client.write_eeprom([0], 0) }.to raise_error(RTLSDR::OperationFailedError, /not supported via TCP/)
    end

    it "raises error for dump_eeprom" do
      expect { client.dump_eeprom }.to raise_error(RTLSDR::OperationFailedError, /not supported via TCP/)
    end
  end

  describe "#info" do
    let(:client) { described_class.new(host, port) }

    it "returns device info hash" do
      info = client.info
      expect(info).to be_a(Hash)
      expect(info[:host]).to eq(host)
      expect(info[:port]).to eq(port)
      expect(info[:tuner_type]).to eq(5)
      expect(info[:tuner_name]).to eq("Rafael Micro R820T")
    end
  end

  describe "#inspect" do
    let(:client) { described_class.new(host, port) }

    it "returns readable string when open" do
      expect(client.inspect).to include("RTLSDR::TcpClient")
      expect(client.inspect).to include(host)
      expect(client.inspect).to include("R820T")
    end

    it "shows closed status after close" do
      client.close
      expect(client.inspect).to include("closed")
    end
  end
end

RSpec.describe RTLSDR do
  describe ".connect" do
    let(:mock_socket) { instance_double(Socket) }
    let(:valid_header) { "RTL0" + [5].pack("N") + [29].pack("N") }

    before do
      allow(Socket).to receive(:tcp).and_return(mock_socket)
      allow(mock_socket).to receive(:setsockopt)
      allow(mock_socket).to receive(:read).with(12).and_return(valid_header)
      allow(mock_socket).to receive(:closed?).and_return(false)
    end

    it "returns a TcpClient instance" do
      client = described_class.connect("localhost")
      expect(client).to be_a(RTLSDR::TcpClient)
    end

    it "uses default port when not specified" do
      expect(Socket).to receive(:tcp).with("localhost", 1234, connect_timeout: 10)
      described_class.connect("localhost")
    end

    it "uses custom port when specified" do
      expect(Socket).to receive(:tcp).with("localhost", 5555, connect_timeout: 10)
      described_class.connect("localhost", 5555)
    end

    it "passes timeout option" do
      expect(Socket).to receive(:tcp).with("localhost", 1234, connect_timeout: 30)
      described_class.connect("localhost", timeout: 30)
    end
  end
end
