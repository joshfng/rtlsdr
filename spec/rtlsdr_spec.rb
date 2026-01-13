# frozen_string_literal: true

require "spec_helper"

RSpec.describe RTLSDR do
  describe "module methods" do
    it "has a version number" do
      expect(RTLSDR::VERSION).not_to be_nil
    end

    it "can check device count" do
      expect { described_class.device_count }.not_to raise_error
      expect(described_class.device_count).to be >= 0
    end

    describe ".device_name" do
      it "returns device name" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_name).and_return("Generic RTL2832U OEM")
        expect(described_class.device_name(0)).to eq("Generic RTL2832U OEM")
      end

      it "passes correct index to FFI" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_name).and_return("Device")
        expect(RTLSDR::FFI).to receive(:rtlsdr_get_device_name).with(2)
        described_class.device_name(2)
      end
    end

    describe ".device_usb_strings" do
      context "when successful" do
        before do
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_usb_strings) do |_index, manufact, product, serial|
            manufact.replace("Realtek          " + " " * 240)
            product.replace("RTL2838UHIDIR    " + " " * 240)
            serial.replace("00000001         " + " " * 240)
            0
          end
        end

        it "returns hash with USB strings" do
          result = described_class.device_usb_strings(0)
          expect(result).to be_a(Hash)
          expect(result).to include(:manufacturer, :product, :serial)
        end

        it "strips trailing spaces" do
          result = described_class.device_usb_strings(0)
          expect(result[:manufacturer]).to eq("Realtek")
          expect(result[:product]).to eq("RTL2838UHIDIR")
          expect(result[:serial]).to eq("00000001")
        end
      end

      context "when FFI call fails" do
        before do
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_usb_strings).and_return(-1)
        end

        it "returns nil" do
          expect(described_class.device_usb_strings(0)).to be_nil
        end
      end
    end

    describe ".find_device_by_serial" do
      context "when device is found" do
        before do
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_index_by_serial).and_return(2)
        end

        it "returns device index" do
          result = described_class.find_device_by_serial("00000001")
          expect(result).to eq(2)
        end

        it "passes serial number to FFI" do
          expect(RTLSDR::FFI).to receive(:rtlsdr_get_index_by_serial).with("00000001")
          described_class.find_device_by_serial("00000001")
        end
      end

      context "when device is not found" do
        before do
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_index_by_serial).and_return(-1)
        end

        it "returns nil" do
          expect(described_class.find_device_by_serial("99999999")).to be_nil
        end
      end

      context "when error occurs" do
        before do
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_index_by_serial).and_return(-2)
        end

        it "returns nil" do
          expect(described_class.find_device_by_serial("invalid")).to be_nil
        end
      end
    end

    describe ".devices" do
      it "can list devices" do
        expect { described_class.devices }.not_to raise_error
        expect(described_class.devices).to be_an(Array)
      end

      it "returns empty array when no devices" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_count).and_return(0)
        expect(described_class.devices).to eq([])
      end

      context "with multiple devices" do
        before do
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_count).and_return(3)
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_name) do |index|
            "Device #{index}"
          end
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_usb_strings) do |index, manufact, product, serial|
            manufact.replace("Manufacturer #{index}" + " " * 240)
            product.replace("Product #{index}     " + " " * 240)
            serial.replace("Serial #{index}      " + " " * 240)
            0
          end
        end

        it "returns array with correct number of devices" do
          devices = described_class.devices
          expect(devices.length).to eq(3)
        end

        it "includes index, name, and usb_strings for each device" do
          devices = described_class.devices
          devices.each do |device|
            expect(device).to include(:index, :name, :usb_strings)
          end
        end

        it "maps indices correctly" do
          devices = described_class.devices
          expect(devices[0][:index]).to eq(0)
          expect(devices[1][:index]).to eq(1)
          expect(devices[2][:index]).to eq(2)
        end

        it "maps names correctly" do
          devices = described_class.devices
          expect(devices[0][:name]).to eq("Device 0")
          expect(devices[1][:name]).to eq("Device 1")
          expect(devices[2][:name]).to eq("Device 2")
        end

        it "maps USB strings correctly" do
          devices = described_class.devices
          expect(devices[0][:usb_strings][:manufacturer]).to eq("Manufacturer 0")
          expect(devices[1][:usb_strings][:product]).to eq("Product 1")
          expect(devices[2][:usb_strings][:serial]).to eq("Serial 2")
        end
      end

      context "when USB strings fail for a device" do
        before do
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_count).and_return(1)
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_name).and_return("Device 0")
          allow(RTLSDR::FFI).to receive(:rtlsdr_get_device_usb_strings).and_return(-1)
        end

        it "includes nil for usb_strings" do
          devices = described_class.devices
          expect(devices[0][:usb_strings]).to be_nil
        end
      end
    end
  end

  describe "device opening" do
    context "when no devices available" do
      before do
        allow(RTLSDR::FFI).to receive_messages(rtlsdr_get_device_count: 0, rtlsdr_open: -1)
      end

      it "raises error when trying to open non-existent device" do
        expect { described_class.open(0) }.to raise_error(RTLSDR::DeviceNotFoundError)
      end
    end
  end

  describe RTLSDR::DSP do
    let(:test_data) { [128, 130, 126, 132, 124, 134, 122, 136] }
    let(:complex_samples) do
      samples = []
      (0...test_data.length).step(2) do |i|
        i_sample = (test_data[i] - 128) / 128.0
        q_sample = (test_data[i + 1] - 128) / 128.0
        samples << Complex(i_sample, q_sample)
      end
      samples
    end

    describe ".iq_to_complex" do
      it "converts IQ data to complex samples" do
        result = described_class.iq_to_complex(test_data)
        expect(result).to be_an(Array)
        expect(result.first).to be_a(Complex)
        expect(result.length).to eq(test_data.length / 2)
      end
    end

    describe ".average_power" do
      it "calculates average power" do
        power = described_class.average_power(complex_samples)
        expect(power).to be_a(Numeric)
        expect(power).to be >= 0
      end

      it "returns 0 for empty array" do
        expect(described_class.average_power([])).to eq(0.0)
      end
    end

    describe ".magnitude" do
      it "returns magnitude of complex samples" do
        magnitudes = described_class.magnitude(complex_samples)
        expect(magnitudes).to be_an(Array)
        expect(magnitudes.length).to eq(complex_samples.length)
        expect(magnitudes.all? { |m| m >= 0 }).to be true
      end
    end

    describe ".phase" do
      it "returns phase of complex samples" do
        phases = described_class.phase(complex_samples)
        expect(phases).to be_an(Array)
        expect(phases.length).to eq(complex_samples.length)
        expect(phases.all? { |p| p.between?(-Math::PI, Math::PI) }).to be true
      end
    end

    describe ".remove_dc" do
      it "removes DC component" do
        filtered = described_class.remove_dc(complex_samples)
        expect(filtered).to be_an(Array)
        expect(filtered.length).to eq(complex_samples.length)
      end

      it "returns original array when empty" do
        expect(described_class.remove_dc([])).to eq([])
      end
    end

    describe ".find_peak" do
      let(:power_spectrum) { [1.0, 3.0, 2.0, 5.0, 1.5] }

      it "finds peak index and value" do
        index, power = described_class.find_peak(power_spectrum)
        expect(index).to eq(3)
        expect(power).to eq(5.0)
      end

      it "handles empty spectrum" do
        index, power = described_class.find_peak([])
        expect(index).to eq(0)
        expect(power).to eq(0.0)
      end
    end
  end

  describe RTLSDR::Scanner do
    let(:mock_device) { instance_double(RTLSDR::Device) }
    let(:scanner) do
      described_class.new(mock_device,
                          start_freq: 100_000_000,
                          end_freq: 101_000_000,
                          step_size: 1_000_000)
    end

    describe "#initialize" do
      it "creates scanner with correct parameters" do
        expect(scanner.start_freq).to eq(100_000_000)
        expect(scanner.end_freq).to eq(101_000_000)
        expect(scanner.step_size).to eq(1_000_000)
      end
    end

    describe "#frequencies" do
      it "returns correct frequency range" do
        freqs = scanner.frequencies
        expect(freqs).to eq([100_000_000, 101_000_000])
      end
    end

    describe "#frequency_count" do
      it "calculates correct frequency count" do
        expect(scanner.frequency_count).to eq(2)
      end
    end

    describe "#configure" do
      it "updates scan parameters" do
        scanner.configure(start_freq: 200_000_000, step_size: 500_000)
        expect(scanner.start_freq).to eq(200_000_000)
        expect(scanner.step_size).to eq(500_000)
      end
    end
  end
end
