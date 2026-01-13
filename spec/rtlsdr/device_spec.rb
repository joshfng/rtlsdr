# frozen_string_literal: true

require "spec_helper"

RSpec.describe RTLSDR::Device do
  let(:mock_handle) { FFI::MemoryPointer.new(:pointer) }
  let(:device_index) { 0 }

  # Helper to create device without opening
  def create_mock_device
    device = described_class.allocate
    device.instance_variable_set(:@index, device_index)
    device.instance_variable_set(:@handle, mock_handle)
    device.instance_variable_set(:@streaming, false)
    device.instance_variable_set(:@async_thread, nil)
    device.instance_variable_set(:@buffer_reset_done, false)
    device
  end

  describe "#initialize" do
    context "when device exists" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_open) do |dev_ptr, _index|
          dev_ptr.write_pointer(mock_handle)
          0
        end
      end

      it "opens the device successfully" do
        device = described_class.new(0)
        expect(device).to be_open
        expect(device.index).to eq(0)
      end
    end

    context "when device does not exist" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_open).and_return(-1)
      end

      it "raises DeviceNotFoundError" do
        expect { described_class.new(0) }.to raise_error(RTLSDR::DeviceNotFoundError, /not found/)
      end
    end

    context "when device is already in use" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_open).and_return(-2)
      end

      it "raises DeviceOpenError" do
        expect { described_class.new(0) }.to raise_error(RTLSDR::DeviceOpenError, /already in use/)
      end
    end

    context "when device cannot be opened" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_open).and_return(-3)
      end

      it "raises DeviceOpenError" do
        expect { described_class.new(0) }.to raise_error(RTLSDR::DeviceOpenError, /cannot be opened/)
      end
    end

    context "when unknown error occurs" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_open).and_return(-99)
      end

      it "raises DeviceOpenError with error code" do
        expect { described_class.new(0) }.to raise_error(RTLSDR::DeviceOpenError, /error -99/)
      end
    end
  end

  describe "error handling" do
    let(:device) { create_mock_device }

    describe "DeviceNotOpenError (-1)" do
      it "raises when setting center frequency" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_center_freq).and_return(-1)
        expect { device.center_freq = 100_000_000 }.to raise_error(RTLSDR::DeviceNotOpenError)
      end

      it "raises when setting sample rate" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_sample_rate).and_return(-1)
        expect { device.sample_rate = 2_048_000 }.to raise_error(RTLSDR::DeviceNotOpenError)
      end

      it "raises when setting gain" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain).and_return(-1)
        expect { device.tuner_gain = 400 }.to raise_error(RTLSDR::DeviceNotOpenError)
      end

      it "raises when setting gain mode" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain_mode).and_return(-1)
        expect { device.tuner_gain_mode = true }.to raise_error(RTLSDR::DeviceNotOpenError)
      end

      it "raises when setting frequency correction" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_freq_correction).and_return(-1)
        expect { device.freq_correction = 15 }.to raise_error(RTLSDR::DeviceNotOpenError)
      end

      it "raises when setting AGC mode" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_agc_mode).and_return(-1)
        expect { device.agc_mode = true }.to raise_error(RTLSDR::DeviceNotOpenError)
      end

      it "raises when setting test mode" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_testmode).and_return(-1)
        expect { device.test_mode = true }.to raise_error(RTLSDR::DeviceNotOpenError)
      end

      it "raises when setting direct sampling" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_direct_sampling).and_return(-1)
        expect { device.direct_sampling = 1 }.to raise_error(RTLSDR::DeviceNotOpenError)
      end

      it "raises when setting offset tuning" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_offset_tuning).and_return(-1)
        expect { device.offset_tuning = true }.to raise_error(RTLSDR::DeviceNotOpenError)
      end

      it "raises when setting bias tee" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee).and_return(-1)
        expect { device.bias_tee = true }.to raise_error(RTLSDR::DeviceNotOpenError)
      end

      it "raises when setting tuner bandwidth" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_bandwidth).and_return(-1)
        expect { device.tuner_bandwidth = 2_000_000 }.to raise_error(RTLSDR::DeviceNotOpenError)
      end
    end

    describe "InvalidArgumentError (-2)" do
      it "raises when setting invalid center frequency" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_center_freq).and_return(-2)
        expect { device.center_freq = -1 }.to raise_error(RTLSDR::InvalidArgumentError)
      end

      it "raises when setting invalid sample rate" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_sample_rate).and_return(-2)
        expect { device.sample_rate = -1 }.to raise_error(RTLSDR::InvalidArgumentError)
      end

      it "raises when setting invalid gain" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain).and_return(-2)
        expect { device.tuner_gain = 9999 }.to raise_error(RTLSDR::InvalidArgumentError)
      end
    end

    describe "EEPROMError (-3)" do
      it "raises when reading EEPROM fails" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_read_eeprom).and_return(-3)
        expect { device.read_eeprom(0, 256) }.to raise_error(RTLSDR::EEPROMError)
      end

      it "raises when writing EEPROM fails" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_write_eeprom).and_return(-3)
        expect { device.write_eeprom([0xFF] * 256, 0) }.to raise_error(RTLSDR::EEPROMError)
      end
    end

    describe "OperationFailedError (other errors)" do
      it "raises when reset buffer fails" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_reset_buffer).and_return(-4)
        expect { device.reset_buffer }.to raise_error(RTLSDR::OperationFailedError)
      end

      it "raises when cancel async fails" do
        device.instance_variable_set(:@streaming, true)
        allow(RTLSDR::FFI).to receive(:rtlsdr_cancel_async).and_return(-4)
        expect { device.cancel_async }.to raise_error(RTLSDR::OperationFailedError)
      end
    end
  end

  describe "data conversion" do
    let(:device) { create_mock_device }

    describe "#read_samples" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_reset_buffer).and_return(0)
        allow(RTLSDR::FFI).to receive(:rtlsdr_read_sync) do |_handle, buffer, length, n_read_ptr|
          # Simulate reading IQ data: alternating I and Q values
          # 128 = center (0), 192 = +0.5, 64 = -0.5
          test_data = [192, 192, 64, 64, 128, 192, 192, 128] * (length / 8)
          buffer.write_array_of_uint8(test_data[0...length])
          n_read_ptr.write_int(length)
          0
        end
      end

      it "converts 8-bit IQ to Complex samples" do
        samples = device.read_samples(4)
        expect(samples).to be_an(Array)
        expect(samples.length).to eq(4)
        expect(samples).to all(be_a(Complex))
      end

      it "normalizes to -1.0 to 1.0 range" do
        samples = device.read_samples(4)
        samples.each do |sample|
          expect(sample.real).to be_between(-1.0, 1.0)
          expect(sample.imag).to be_between(-1.0, 1.0)
        end
      end

      it "converts 128 to 0.0 (DC center)" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_read_sync) do |_handle, buffer, _length, n_read_ptr|
          buffer.write_array_of_uint8([128, 128, 128, 128])
          n_read_ptr.write_int(4)
          0
        end

        samples = device.read_samples(2)
        expect(samples[0].real).to be_within(0.01).of(0.0)
        expect(samples[0].imag).to be_within(0.01).of(0.0)
      end

      it "converts 0 to -1.0" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_read_sync) do |_handle, buffer, _length, n_read_ptr|
          buffer.write_array_of_uint8([0, 0])
          n_read_ptr.write_int(2)
          0
        end

        samples = device.read_samples(1)
        expect(samples[0].real).to eq(-1.0)
        expect(samples[0].imag).to eq(-1.0)
      end

      it "converts 255 to ~0.99" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_read_sync) do |_handle, buffer, _length, n_read_ptr|
          buffer.write_array_of_uint8([255, 255])
          n_read_ptr.write_int(2)
          0
        end

        samples = device.read_samples(1)
        expect(samples[0].real).to be_within(0.01).of(0.99)
        expect(samples[0].imag).to be_within(0.01).of(0.99)
      end

      it "pairs I and Q samples correctly" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_read_sync) do |_handle, buffer, _length, n_read_ptr|
          # I=0, Q=255 should give Complex(-1.0, 0.99)
          buffer.write_array_of_uint8([0, 255])
          n_read_ptr.write_int(2)
          0
        end

        samples = device.read_samples(1)
        expect(samples[0].real).to eq(-1.0)
        expect(samples[0].imag).to be_within(0.01).of(0.99)
      end

      it "reads correct number of bytes (2x sample count)" do
        expect(RTLSDR::FFI).to receive(:rtlsdr_read_sync) do |_handle, _buffer, length, n_read_ptr|
          expect(length).to eq(2048) # 1024 samples * 2 bytes
          n_read_ptr.write_int(length)
          0
        end

        device.read_samples(1024)
      end
    end

    describe "#dump_eeprom" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_read_eeprom) do |_handle, data_ptr, offset, length|
          # Fill with test pattern: offset value
          test_data = (offset...(offset + length)).to_a.map { |i| i % 256 }
          data_ptr.write_array_of_uint8(test_data)
          0
        end
      end

      it "returns binary string" do
        dump = device.dump_eeprom
        expect(dump).to be_a(String)
        expect(dump.encoding).to eq(Encoding::ASCII_8BIT)
      end

      it "reads 256 bytes" do
        dump = device.dump_eeprom
        expect(dump.length).to eq(256)
      end

      it "reads from offset 0" do
        expect(RTLSDR::FFI).to receive(:rtlsdr_read_eeprom).with(mock_handle, anything, 0, 256)
        device.dump_eeprom
      end

      it "converts byte array to binary string" do
        dump = device.dump_eeprom
        # Check first few bytes match expected pattern
        expect(dump.bytes[0]).to eq(0)
        expect(dump.bytes[1]).to eq(1)
        expect(dump.bytes[255]).to eq(255)
      end
    end

    describe "#usb_strings" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_usb_strings) do |_handle, manufact, product, serial|
          manufact.replace("Realtek          " + " " * 240)
          product.replace("RTL2838UHIDIR    " + " " * 240)
          serial.replace("00000001         " + " " * 240)
          0
        end
      end

      it "returns hash with USB info" do
        strings = device.usb_strings
        expect(strings).to be_a(Hash)
        expect(strings).to include(:manufacturer, :product, :serial)
      end

      it "strips trailing spaces" do
        strings = device.usb_strings
        expect(strings[:manufacturer]).to eq("Realtek")
        expect(strings[:product]).to eq("RTL2838UHIDIR")
        expect(strings[:serial]).to eq("00000001")
      end

      it "caches result on subsequent calls" do
        expect(RTLSDR::FFI).to receive(:rtlsdr_get_usb_strings).once
        device.usb_strings
        device.usb_strings # Should use cached value
      end

      it "raises error when FFI call fails" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_usb_strings).and_return(-1)
        expect { device.usb_strings }.to raise_error(RTLSDR::DeviceNotOpenError)
      end
    end
  end

  describe "gain control" do
    let(:device) { create_mock_device }

    describe "#tuner_gains" do
      it "returns empty array when count is zero" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_tuner_gains).and_return(0)
        expect(device.tuner_gains).to eq([])
      end

      it "returns empty array when count is negative" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_tuner_gains).and_return(-1)
        expect(device.tuner_gains).to eq([])
      end

      it "returns gain array when successful" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_tuner_gains) do |_handle, gains_ptr|
          if gains_ptr.nil?
            5 # Return count
          else
            gains_ptr.write_array_of_int([0, 9, 14, 27, 37])
            5
          end
        end

        gains = device.tuner_gains
        expect(gains).to eq([0, 9, 14, 27, 37])
      end

      it "returns empty array when second call fails" do
        call_count = 0
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_tuner_gains) do |_handle, gains_ptr|
          call_count += 1
          call_count == 1 ? 5 : -1
        end

        expect(device.tuner_gains).to eq([])
      end
    end

    describe "convenience methods" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain_mode).and_return(0)
      end

      it "#manual_gain_mode! sets manual mode" do
        expect(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain_mode).with(mock_handle, 1)
        device.manual_gain_mode!
      end

      it "#auto_gain_mode! sets auto mode" do
        expect(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain_mode).with(mock_handle, 0)
        device.auto_gain_mode!
      end

      it "#agc_mode! enables AGC" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_agc_mode).and_return(0)
        expect(RTLSDR::FFI).to receive(:rtlsdr_set_agc_mode).with(mock_handle, 1)
        device.agc_mode!
      end
    end
  end

  describe "direct sampling" do
    let(:device) { create_mock_device }

    describe "#direct_sampling" do
      it "returns mode value when successful" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_direct_sampling).and_return(1)
        expect(device.direct_sampling).to eq(1)
      end

      it "returns nil when error occurs" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_direct_sampling).and_return(-1)
        expect(device.direct_sampling).to be_nil
      end
    end
  end

  describe "offset tuning" do
    let(:device) { create_mock_device }

    describe "#offset_tuning" do
      it "returns true when enabled" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_offset_tuning).and_return(1)
        expect(device.offset_tuning).to be true
      end

      it "returns false when disabled" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_offset_tuning).and_return(0)
        expect(device.offset_tuning).to be false
      end

      it "returns nil when error occurs" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_offset_tuning).and_return(-1)
        expect(device.offset_tuning).to be_nil
      end

      it "#offset_tuning! enables offset tuning" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_offset_tuning).and_return(0)
        expect(RTLSDR::FFI).to receive(:rtlsdr_set_offset_tuning).with(mock_handle, 1)
        device.offset_tuning!
      end
    end
  end

  describe "bias tee" do
    let(:device) { create_mock_device }

    before do
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee).and_return(0)
    end

    it "#enable_bias_tee sets bias tee to true" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee).with(mock_handle, 1)
      device.enable_bias_tee
    end

    it "#disable_bias_tee sets bias tee to false" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee).with(mock_handle, 0)
      device.disable_bias_tee
    end

    it "#bias_tee! enables bias tee" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee).with(mock_handle, 1)
      device.bias_tee!
    end

    describe "#set_bias_tee_gpio" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee_gpio).and_return(0)
      end

      it "sets GPIO high when enabled" do
        expect(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee_gpio).with(mock_handle, 5, 1)
        result = device.set_bias_tee_gpio(5, true)
        expect(result).to be true
      end

      it "sets GPIO low when disabled" do
        expect(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee_gpio).with(mock_handle, 5, 0)
        result = device.set_bias_tee_gpio(5, false)
        expect(result).to be false
      end

      it "raises error when operation fails" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee_gpio).and_return(-1)
        expect { device.set_bias_tee_gpio(5, true) }.to raise_error(RTLSDR::DeviceNotOpenError)
      end
    end
  end

  describe "crystal oscillator" do
    let(:device) { create_mock_device }

    describe "#set_xtal_freq" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_xtal_freq).and_return(0)
      end

      it "sets both RTL and tuner frequencies" do
        expect(RTLSDR::FFI).to receive(:rtlsdr_set_xtal_freq).with(mock_handle, 28_800_000, 28_800_000)
        result = device.set_xtal_freq(28_800_000, 28_800_000)
        expect(result).to eq([28_800_000, 28_800_000])
      end

      it "raises error when operation fails" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_set_xtal_freq).and_return(-1)
        expect { device.set_xtal_freq(28_800_000, 28_800_000) }.to raise_error(RTLSDR::DeviceNotOpenError)
      end
    end

    describe "#xtal_freq" do
      before do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_xtal_freq) do |_handle, rtl_ptr, tuner_ptr|
          rtl_ptr.write_uint32(28_800_000)
          tuner_ptr.write_uint32(28_800_000)
          0
        end
      end

      it "returns array of frequencies" do
        freqs = device.xtal_freq
        expect(freqs).to eq([28_800_000, 28_800_000])
      end

      it "raises error when operation fails" do
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_xtal_freq).and_return(-1)
        expect { device.xtal_freq }.to raise_error(RTLSDR::DeviceNotOpenError)
      end
    end
  end

  describe "#set_tuner_if_gain" do
    let(:device) { create_mock_device }

    before do
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_if_gain).and_return(0)
    end

    it "sets IF gain for specific stage" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_if_gain).with(mock_handle, 3, 90)
      result = device.set_tuner_if_gain(3, 90)
      expect(result).to eq(90)
    end

    it "raises error when operation fails" do
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_if_gain).and_return(-1)
      expect { device.set_tuner_if_gain(3, 90) }.to raise_error(RTLSDR::DeviceNotOpenError)
    end
  end

  describe "#test_mode!" do
    let(:device) { create_mock_device }

    before do
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_testmode).and_return(0)
    end

    it "enables test mode" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_testmode).with(mock_handle, 1)
      device.test_mode!
    end
  end

  describe "#close" do
    let(:device) { create_mock_device }

    before do
      allow(RTLSDR::FFI).to receive(:rtlsdr_close).and_return(0)
    end

    it "closes the device" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_close).with(mock_handle)
      device.close
      expect(device).to be_closed
    end

    it "cancels async streaming before closing" do
      device.instance_variable_set(:@streaming, true)
      allow(RTLSDR::FFI).to receive(:rtlsdr_cancel_async).and_return(0)

      expect(RTLSDR::FFI).to receive(:rtlsdr_cancel_async).ordered
      expect(RTLSDR::FFI).to receive(:rtlsdr_close).ordered

      device.close
    end

    it "is safe to call multiple times" do
      device.close
      expect { device.close }.not_to raise_error
    end

    it "raises error when close fails" do
      allow(RTLSDR::FFI).to receive(:rtlsdr_close).and_return(-1)
      expect { device.close }.to raise_error(RTLSDR::DeviceNotOpenError)
    end
  end

  describe "aliases" do
    let(:device) { create_mock_device }

    it "aliases frequency to center_freq" do
      allow(RTLSDR::FFI).to receive(:rtlsdr_get_center_freq).and_return(100_000_000)
      expect(device.frequency).to eq(device.center_freq)
    end

    it "aliases frequency= to center_freq=" do
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_center_freq).and_return(0)
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_center_freq).with(mock_handle, 100_000_000)
      device.frequency = 100_000_000
    end

    it "aliases gain to tuner_gain" do
      allow(RTLSDR::FFI).to receive(:rtlsdr_get_tuner_gain).and_return(400)
      expect(device.gain).to eq(device.tuner_gain)
    end

    it "aliases gain= to tuner_gain=" do
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain).and_return(0)
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain).with(mock_handle, 400)
      device.gain = 400
    end

    it "aliases samp_rate to sample_rate" do
      allow(RTLSDR::FFI).to receive(:rtlsdr_get_sample_rate).and_return(2_048_000)
      expect(device.samp_rate).to eq(device.sample_rate)
    end

    it "aliases samp_rate= to sample_rate=" do
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_sample_rate).and_return(0)
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_sample_rate).with(mock_handle, 2_048_000)
      device.samp_rate = 2_048_000
    end
  end

  describe "#configure" do
    let(:device) { create_mock_device }

    before do
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_center_freq).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_sample_rate).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain_mode).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_freq_correction).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_bandwidth).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_agc_mode).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_testmode).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_direct_sampling).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_set_offset_tuning).and_return(0)
    end

    it "sets frequency when provided" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_center_freq).with(mock_handle, 100_000_000)
      device.configure(frequency: 100_000_000)
    end

    it "sets sample rate when provided" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_sample_rate).with(mock_handle, 2_048_000)
      device.configure(sample_rate: 2_048_000)
    end

    it "sets gain and enables manual mode when gain provided" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain_mode).with(mock_handle, 1)
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_gain).with(mock_handle, 400)
      device.configure(gain: 400)
    end

    it "sets freq_correction option" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_freq_correction).with(mock_handle, 15)
      device.configure(freq_correction: 15)
    end

    it "sets bandwidth option" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_tuner_bandwidth).with(mock_handle, 2_000_000)
      device.configure(bandwidth: 2_000_000)
    end

    it "sets agc_mode option" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_agc_mode).with(mock_handle, 1)
      device.configure(agc_mode: true)
    end

    it "sets test_mode option" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_testmode).with(mock_handle, 1)
      device.configure(test_mode: true)
    end

    it "sets bias_tee option" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_bias_tee).with(mock_handle, 1)
      device.configure(bias_tee: true)
    end

    it "sets direct_sampling option" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_direct_sampling).with(mock_handle, 1)
      device.configure(direct_sampling: 1)
    end

    it "sets offset_tuning option" do
      expect(RTLSDR::FFI).to receive(:rtlsdr_set_offset_tuning).with(mock_handle, 1)
      device.configure(offset_tuning: true)
    end

    it "returns self for chaining" do
      result = device.configure(frequency: 100_000_000)
      expect(result).to eq(device)
    end

    it "ignores unknown options" do
      expect { device.configure(unknown_option: 123) }.not_to raise_error
    end
  end

  describe "#read_samples_async" do
    let(:device) { create_mock_device }

    it "raises ArgumentError when no block provided" do
      expect { device.read_samples_async }.to raise_error(ArgumentError, /Block required/)
    end

    it "raises OperationFailedError when already streaming" do
      device.instance_variable_set(:@streaming, true)
      expect { device.read_samples_async { |_| } }.to raise_error(RTLSDR::OperationFailedError, /Already streaming/)
    end
  end

  describe "#info" do
    let(:device) { create_mock_device }

    before do
      allow(device).to receive(:name).and_return("Generic RTL2832U OEM")
      allow(device).to receive(:usb_strings).and_return({ manufacturer: "Realtek", product: "RTL2838UHIDIR", serial: "00000001" })
      allow(device).to receive(:tuner_type).and_return(5)
      allow(device).to receive(:tuner_name).and_return("Rafael Micro R820T")
      allow(RTLSDR::FFI).to receive(:rtlsdr_get_center_freq).and_return(100_000_000)
      allow(RTLSDR::FFI).to receive(:rtlsdr_get_sample_rate).and_return(2_048_000)
      allow(RTLSDR::FFI).to receive(:rtlsdr_get_tuner_gain).and_return(400)
      allow(device).to receive(:tuner_gains).and_return([0, 9, 14, 27, 37, 77, 87, 125, 144, 157, 166, 197, 207, 229, 254, 280, 297, 328, 338, 364, 372, 386, 402, 421, 434, 439, 445, 480, 496])
      allow(RTLSDR::FFI).to receive(:rtlsdr_get_freq_correction).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_get_direct_sampling).and_return(0)
      allow(RTLSDR::FFI).to receive(:rtlsdr_get_offset_tuning).and_return(0)
    end

    it "returns hash with device information" do
      info = device.info
      expect(info).to be_a(Hash)
      expect(info).to include(
        :index, :name, :usb_strings, :tuner_type, :tuner_name,
        :center_freq, :sample_rate, :tuner_gain, :tuner_gains,
        :freq_correction, :direct_sampling, :offset_tuning
      )
    end

    it "includes correct device index" do
      expect(device.info[:index]).to eq(0)
    end
  end

  describe "#inspect" do
    let(:device) { create_mock_device }

    context "when device is open" do
      before do
        allow(device).to receive(:name).and_return("Generic RTL2832U OEM")
        allow(device).to receive(:tuner_name).and_return("Rafael Micro R820T")
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_center_freq).and_return(100_000_000)
        allow(RTLSDR::FFI).to receive(:rtlsdr_get_sample_rate).and_return(2_048_000)
      end

      it "includes device information" do
        str = device.inspect
        expect(str).to include("RTLSDR::Device")
        expect(str).to include("index=0")
        expect(str).to include("Generic RTL2832U OEM")
        expect(str).to include("Rafael Micro R820T")
        expect(str).to include("100000000Hz")
        expect(str).to include("2048000Hz")
      end
    end

    context "when device is closed" do
      before do
        device.instance_variable_set(:@handle, nil)
      end

      it "shows closed status" do
        str = device.inspect
        expect(str).to include("RTLSDR::Device")
        expect(str).to include("index=0")
        expect(str).to include("closed")
      end
    end
  end
end
