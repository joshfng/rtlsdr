# frozen_string_literal: true

require "ffi"

module RTLSDR
  # High-level interface to RTL-SDR devices
  #
  # The Device class provides a Ruby-idiomatic interface to RTL-SDR dongles,
  # wrapping the low-level librtlsdr C API with convenient methods and automatic
  # resource management. It supports both synchronous and asynchronous sample
  # reading, comprehensive device configuration, and implements Enumerable for
  # streaming operations.
  #
  # Features:
  # * Automatic device lifecycle management (open/close)
  # * Frequency, gain, and sample rate control with validation
  # * Multiple gain modes (manual, automatic, AGC)
  # * Synchronous and asynchronous sample reading
  # * IQ sample conversion to Ruby Complex numbers
  # * EEPROM access and bias tee control
  # * Enumerable interface for continuous streaming
  # * Comprehensive error handling with custom exceptions
  #
  # @example Basic device setup
  #   device = RTLSDR::Device.new(0)
  #   device.configure(
  #     frequency: 100_000_000,    # 100 MHz
  #     sample_rate: 2_048_000,    # 2.048 MSPS
  #     gain: 496                   # 49.6 dB
  #   )
  #
  # @example Streaming samples
  #   device.each(samples_per_read: 1024) do |samples|
  #     power = RTLSDR::DSP.average_power(samples)
  #     puts "Average power: #{power}"
  #   end
  #
  # @example Asynchronous reading
  #   device.read_samples_async do |samples|
  #     # Process samples in real-time
  #     spectrum = RTLSDR::DSP.power_spectrum(samples)
  #   end
  class Device
    include Enumerable

    # @return [Integer] Device index (0-based)
    attr_reader :index
    # @return [FFI::Pointer] Internal device handle pointer
    attr_reader :handle

    # Create a new RTL-SDR device instance
    #
    # Opens the specified RTL-SDR device and prepares it for use. The device
    # will be automatically opened during initialization.
    #
    # @param [Integer] index Device index to open (default: 0)
    # @raise [DeviceNotFoundError] if device doesn't exist
    # @raise [DeviceOpenError] if device cannot be opened
    # @example Create device instance
    #   device = RTLSDR::Device.new(0)
    #   puts "Opened: #{device.name}"
    def initialize(index = 0)
      @index = index
      @handle = nil
      @streaming = false
      @async_thread = nil
      @buffer_reset_done = false
      open_device
    end

    # Device lifecycle
    def open?
      !@handle.nil?
    end

    # Close the RTL-SDR device
    #
    # Closes the device handle and releases system resources. If async reading
    # is active, it will be cancelled first. After closing, the device cannot
    # be used until reopened.
    #
    # @return [void]
    # @example Close device
    #   device.close
    #   puts "Device closed"
    def close
      return unless open?

      cancel_async if streaming?
      result = FFI.rtlsdr_close(@handle)
      @handle = nil
      check_result(result, "Failed to close device")
    end

    # Check if the device is closed
    #
    # @return [Boolean] true if device is closed, false if open
    def closed?
      !open?
    end

    # Device information
    def name
      RTLSDR.device_name(@index)
    end

    # Get USB device strings
    #
    # Retrieves the USB manufacturer, product, and serial number strings
    # for this device. Results are cached after the first call.
    #
    # @return [Hash] Hash with :manufacturer, :product, :serial keys
    # @example Get USB information
    #   usb_info = device.usb_strings
    #   puts "#{usb_info[:manufacturer]} #{usb_info[:product]}"
    def usb_strings
      return @usb_strings if @usb_strings

      manufact = " " * 256
      product = " " * 256
      serial = " " * 256

      result = FFI.rtlsdr_get_usb_strings(@handle, manufact, product, serial)
      check_result(result, "Failed to get USB strings")

      @usb_strings = {
        manufacturer: manufact.strip,
        product: product.strip,
        serial: serial.strip
      }
    end

    # Get the tuner type constant
    #
    # Returns the tuner type as one of the RTLSDR_TUNER_* constants.
    # The result is cached after the first call.
    #
    # @return [Integer] Tuner type constant
    # @see RTLSDR::FFI::RTLSDR_TUNER_*
    def tuner_type
      @tuner_type ||= FFI.rtlsdr_get_tuner_type(@handle)
    end

    # Get human-readable tuner name
    #
    # @return [String] Tuner chip name and manufacturer
    # @example Get tuner information
    #   puts "Tuner: #{device.tuner_name}"
    def tuner_name
      FFI.tuner_type_name(tuner_type)
    end

    # Frequency control
    def center_freq=(freq)
      result = FFI.rtlsdr_set_center_freq(@handle, freq)
      check_result(result, "Failed to set center frequency")
    end

    # Get the current center frequency
    #
    # @return [Integer] Center frequency in Hz
    def center_freq
      FFI.rtlsdr_get_center_freq(@handle)
    end
    # @!method frequency
    #   Alias for {#center_freq}
    #   @return [Integer] Center frequency in Hz
    alias frequency center_freq
    # @!method frequency=
    #   Alias for {#center_freq=}
    alias frequency= center_freq=

    # Set frequency correction in PPM
    #
    # @param [Integer] ppm Frequency correction in parts per million
    # @example Set 15 PPM correction
    #   device.freq_correction = 15
    def freq_correction=(ppm)
      result = FFI.rtlsdr_set_freq_correction(@handle, ppm)
      check_result(result, "Failed to set frequency correction")
    end

    # Get current frequency correction
    #
    # @return [Integer] Frequency correction in PPM
    def freq_correction
      FFI.rtlsdr_get_freq_correction(@handle)
    end

    # Crystal oscillator frequencies
    def set_xtal_freq(rtl_freq, tuner_freq)
      result = FFI.rtlsdr_set_xtal_freq(@handle, rtl_freq, tuner_freq)
      check_result(result, "Failed to set crystal frequencies")
      [rtl_freq, tuner_freq]
    end

    # Get crystal oscillator frequencies
    #
    # @return [Array<Integer>] Array of [rtl_freq, tuner_freq] in Hz
    def xtal_freq
      rtl_freq_ptr = ::FFI::MemoryPointer.new(:uint32)
      tuner_freq_ptr = ::FFI::MemoryPointer.new(:uint32)

      result = FFI.rtlsdr_get_xtal_freq(@handle, rtl_freq_ptr, tuner_freq_ptr)
      check_result(result, "Failed to get crystal frequencies")

      [rtl_freq_ptr.read_uint32, tuner_freq_ptr.read_uint32]
    end

    # Gain control
    def tuner_gains
      # First call to get count
      count = FFI.rtlsdr_get_tuner_gains(@handle, nil)
      return [] if count <= 0

      # Second call to get actual gains
      gains_ptr = ::FFI::MemoryPointer.new(:int, count)
      result = FFI.rtlsdr_get_tuner_gains(@handle, gains_ptr)
      return [] if result <= 0

      gains_ptr.read_array_of_int(result)
    end

    # Set tuner gain in tenths of dB
    #
    # @param [Integer] gain Gain in tenths of dB (e.g., 496 = 49.6 dB)
    # @example Set 40 dB gain
    #   device.tuner_gain = 400
    def tuner_gain=(gain)
      result = FFI.rtlsdr_set_tuner_gain(@handle, gain)
      check_result(result, "Failed to set tuner gain")
    end

    # Get current tuner gain
    #
    # @return [Integer] Current gain in tenths of dB
    def tuner_gain
      FFI.rtlsdr_get_tuner_gain(@handle)
    end
    # @!method gain
    #   Alias for {#tuner_gain}
    #   @return [Integer] Current gain in tenths of dB
    alias gain tuner_gain
    # @!method gain=
    #   Alias for {#tuner_gain=}
    alias gain= tuner_gain=

    # Set gain mode (manual or automatic)
    #
    # @param [Boolean] manual true for manual gain mode, false for automatic
    def tuner_gain_mode=(manual)
      mode = manual ? 1 : 0
      result = FFI.rtlsdr_set_tuner_gain_mode(@handle, mode)
      check_result(result, "Failed to set gain mode")
    end

    # Enable manual gain mode
    #
    # @return [Boolean] true
    def manual_gain_mode!
      self.tuner_gain_mode = true
    end

    # Enable automatic gain mode
    #
    # @return [Boolean] false
    def auto_gain_mode!
      self.tuner_gain_mode = false
    end

    # Set IF gain for specific stage
    #
    # @param [Integer] stage IF stage number
    # @param [Integer] gain Gain value in tenths of dB
    # @return [Integer] The gain value that was set
    def set_tuner_if_gain(stage, gain)
      result = FFI.rtlsdr_set_tuner_if_gain(@handle, stage, gain)
      check_result(result, "Failed to set IF gain")
      gain
    end

    # Set tuner bandwidth
    #
    # @param [Integer] bw Bandwidth in Hz
    def tuner_bandwidth=(bw)
      result = FFI.rtlsdr_set_tuner_bandwidth(@handle, bw)
      check_result(result, "Failed to set bandwidth")
    end

    # Sample rate control
    def sample_rate=(rate)
      result = FFI.rtlsdr_set_sample_rate(@handle, rate)
      check_result(result, "Failed to set sample rate")
    end

    # Get current sample rate
    #
    # @return [Integer] Sample rate in Hz
    def sample_rate
      FFI.rtlsdr_get_sample_rate(@handle)
    end
    # @!method samp_rate
    #   Alias for {#sample_rate}
    #   @return [Integer] Sample rate in Hz
    alias samp_rate sample_rate
    # @!method samp_rate=
    #   Alias for {#sample_rate=}
    alias samp_rate= sample_rate=

    # Mode control
    def test_mode=(enabled)
      mode = enabled ? 1 : 0
      result = FFI.rtlsdr_set_testmode(@handle, mode)
      check_result(result, "Failed to set test mode")
    end

    # Enable test mode
    #
    # @return [Boolean] true
    def test_mode!
      self.test_mode = true
    end

    # Set automatic gain control mode
    #
    # @param [Boolean] enabled true to enable AGC, false to disable
    def agc_mode=(enabled)
      mode = enabled ? 1 : 0
      result = FFI.rtlsdr_set_agc_mode(@handle, mode)
      check_result(result, "Failed to set AGC mode")
    end

    # Enable automatic gain control
    #
    # @return [Boolean] true
    def agc_mode!
      self.agc_mode = true
    end

    # Set direct sampling mode
    #
    # @param [Integer] mode Direct sampling mode (0=off, 1=I-ADC, 2=Q-ADC)
    def direct_sampling=(mode)
      result = FFI.rtlsdr_set_direct_sampling(@handle, mode)
      check_result(result, "Failed to set direct sampling")
    end

    # Get current direct sampling mode
    #
    # @return [Integer, nil] Direct sampling mode or nil on error
    def direct_sampling
      result = FFI.rtlsdr_get_direct_sampling(@handle)
      return nil if result.negative?

      result
    end

    # Set offset tuning mode
    #
    # @param [Boolean] enabled true to enable offset tuning, false to disable
    def offset_tuning=(enabled)
      mode = enabled ? 1 : 0
      result = FFI.rtlsdr_set_offset_tuning(@handle, mode)
      check_result(result, "Failed to set offset tuning")
    end

    # Get current offset tuning mode
    #
    # @return [Boolean, nil] true if enabled, false if disabled, nil on error
    def offset_tuning
      result = FFI.rtlsdr_get_offset_tuning(@handle)
      return nil if result.negative?

      result == 1
    end

    # Enable offset tuning
    #
    # @return [Boolean] true
    def offset_tuning!
      self.offset_tuning = true
    end

    # Bias tee control
    def bias_tee=(enabled)
      mode = enabled ? 1 : 0
      result = FFI.rtlsdr_set_bias_tee(@handle, mode)
      check_result(result, "Failed to set bias tee")
    end

    # Enable bias tee
    #
    # @return [Boolean] true
    def bias_tee!
      self.bias_tee = true
    end

    # Set bias tee GPIO state
    #
    # @param [Integer] gpio GPIO pin number
    # @param [Boolean] enabled true to enable, false to disable
    # @return [Boolean] The enabled state that was set
    def set_bias_tee_gpio(gpio, enabled)
      mode = enabled ? 1 : 0
      result = FFI.rtlsdr_set_bias_tee_gpio(@handle, gpio, mode)
      check_result(result, "Failed to set bias tee GPIO")
      enabled
    end

    # EEPROM access
    def read_eeprom(offset, length)
      data_ptr = ::FFI::MemoryPointer.new(:uint8, length)
      result = FFI.rtlsdr_read_eeprom(@handle, data_ptr, offset, length)
      check_result(result, "Failed to read EEPROM")
      data_ptr.read_array_of_uint8(length)
    end

    # Write data to EEPROM
    #
    # @param [Array<Integer>] data Array of bytes to write
    # @param [Integer] offset EEPROM offset address
    # @return [Integer] Number of bytes written
    def write_eeprom(data, offset)
      data_ptr = ::FFI::MemoryPointer.new(:uint8, data.length)
      data_ptr.write_array_of_uint8(data)
      result = FFI.rtlsdr_write_eeprom(@handle, data_ptr, offset, data.length)
      check_result(result, "Failed to write EEPROM")
      data.length
    end

    # Read the entire EEPROM contents
    #
    # Reads the complete 256-byte EEPROM data from the device and returns it
    # as a binary string suitable for writing to a file.
    #
    # @return [String] Binary string containing the entire EEPROM contents
    # @example Dump EEPROM to file
    #   File.binwrite("eeprom_backup.bin", device.dump_eeprom)
    def dump_eeprom
      data = read_eeprom(0, 256) # RTL-SDR devices have a 256-byte EEPROM
      data.pack("C*") # Convert byte array to binary string
    end

    # Streaming control
    def reset_buffer
      result = FFI.rtlsdr_reset_buffer(@handle)
      check_result(result, "Failed to reset buffer")
    end

    # Read raw IQ data synchronously
    #
    # Reads raw 8-bit IQ data from the device. The buffer is automatically
    # reset on the first read to avoid stale data.
    #
    # @param [Integer] length Number of bytes to read
    # @return [Array<Integer>] Array of 8-bit unsigned integers
    def read_sync(length)
      # Reset buffer before first read to avoid stale data
      reset_buffer unless @buffer_reset_done
      @buffer_reset_done = true

      buffer = ::FFI::MemoryPointer.new(:uint8, length)
      n_read_ptr = ::FFI::MemoryPointer.new(:int)

      result = FFI.rtlsdr_read_sync(@handle, buffer, length, n_read_ptr)
      check_result(result, "Failed to read synchronously")

      n_read = n_read_ptr.read_int
      buffer.read_array_of_uint8(n_read)
    end

    # Read complex samples synchronously
    #
    # Reads the specified number of complex samples from the device and
    # converts them from raw 8-bit IQ data to Ruby Complex numbers.
    #
    # @param [Integer] count Number of complex samples to read (default: 1024)
    # @return [Array<Complex>] Array of complex samples
    # @example Read 2048 samples
    #   samples = device.read_samples(2048)
    #   puts "Read #{samples.length} samples"
    def read_samples(count = 1024)
      # RTL-SDR outputs 8-bit I/Q samples, so we need 2 bytes per complex sample
      data = read_sync(count * 2)

      # Convert to complex numbers (I + jQ)
      samples = []
      (0...data.length).step(2) do |i|
        i_sample = (data[i] - 128) / 128.0      # Convert to -1.0 to 1.0 range
        q_sample = (data[i + 1] - 128) / 128.0  # Convert to -1.0 to 1.0 range
        samples << Complex(i_sample, q_sample)
      end

      samples
    end

    # Check if asynchronous streaming is active
    #
    # @return [Boolean] true if streaming, false otherwise
    def streaming?
      @streaming
    end

    # Read raw IQ data asynchronously
    #
    # Starts asynchronous reading of raw 8-bit IQ data. The provided block
    # will be called for each buffer of data received.
    #
    # @param [Integer] buffer_count Number of buffers to use (default: 15)
    # @param [Integer] buffer_length Length of each buffer in bytes (default: 262144)
    # @yield [Array<Integer>] Block called with each buffer of raw IQ data
    # @return [Thread] Thread object running the async operation
    # @raise [ArgumentError] if no block is provided
    # @raise [OperationFailedError] if already streaming
    def read_async(buffer_count: 15, buffer_length: 262_144, &block)
      raise ArgumentError, "Block required for async reading" unless block_given?
      raise OperationFailedError, "Already streaming" if streaming?

      @streaming = true
      @async_callback = proc do |buf_ptr, len, _ctx|
        data = buf_ptr.read_array_of_uint8(len)
        block.call(data)
      rescue StandardError => e
        puts "Error in async callback: #{e.message}"
        cancel_async
      end

      @async_thread = Thread.new do
        result = FFI.rtlsdr_read_async(@handle, @async_callback, nil, buffer_count, buffer_length)
        @streaming = false
        # Don't raise error for cancellation (-1) or timeout (-5)
        check_result(result, "Async read failed") unless [-1, -5].include?(result)
      end

      @async_thread
    end

    # Read complex samples asynchronously
    #
    # Starts asynchronous reading and converts raw IQ data to complex samples.
    # The provided block will be called for each buffer of complex samples.
    #
    # @param [Integer] buffer_count Number of buffers to use (default: 15)
    # @param [Integer] buffer_length Length of each buffer in bytes (default: 262144)
    # @yield [Array<Complex>] Block called with each buffer of complex samples
    # @return [Thread] Thread object running the async operation
    # @raise [ArgumentError] if no block is provided
    def read_samples_async(buffer_count: 15, buffer_length: 262_144, &block)
      raise ArgumentError, "Block required for async reading" unless block_given?

      read_async(buffer_count: buffer_count, buffer_length: buffer_length) do |data|
        # Convert to complex samples
        samples = []
        (0...data.length).step(2) do |i|
          i_sample = (data[i] - 128) / 128.0
          q_sample = (data[i + 1] - 128) / 128.0
          samples << Complex(i_sample, q_sample)
        end

        block.call(samples)
      end
    end

    # Cancel asynchronous reading operation
    #
    # Stops any active asynchronous reading and cleans up resources.
    # This method is safe to call from within async callbacks.
    #
    # @return [void]
    def cancel_async
      return unless streaming?

      result = FFI.rtlsdr_cancel_async(@handle)
      @streaming = false

      # Only join if we're not calling from within the async thread itself
      if @async_thread && @async_thread != Thread.current
        @async_thread.join(1) # Wait up to 1 second for thread to finish
      end

      @async_thread = nil
      @async_callback = nil

      check_result(result, "Failed to cancel async operation")
    end

    # Enumerable interface for reading samples
    def each(samples_per_read: 1024)
      return enum_for(:each, samples_per_read: samples_per_read) unless block_given?

      loop do
        samples = read_samples(samples_per_read)
        yield samples
      rescue StandardError => e
        break if e.is_a?(Interrupt)

        raise
      end
    end

    # Configuration shortcuts
    def configure(frequency: nil, sample_rate: nil, gain: nil, **options)
      self.center_freq = frequency if frequency
      self.sample_rate = sample_rate if sample_rate

      if gain
        manual_gain_mode!
        self.tuner_gain = gain
      end

      options.each do |key, value|
        case key
        when :freq_correction then self.freq_correction = value
        when :bandwidth then self.tuner_bandwidth = value
        when :agc_mode then self.agc_mode = value
        when :test_mode then self.test_mode = value
        when :bias_tee then self.bias_tee = value
        when :direct_sampling then self.direct_sampling = value
        when :offset_tuning then self.offset_tuning = value
        end
      end

      self
    end

    # Device info as hash
    def info
      {
        index: @index,
        name: name,
        usb_strings: usb_strings,
        tuner_type: tuner_type,
        tuner_name: tuner_name,
        center_freq: center_freq,
        sample_rate: sample_rate,
        tuner_gain: tuner_gain,
        tuner_gains: tuner_gains,
        freq_correction: freq_correction,
        direct_sampling: direct_sampling,
        offset_tuning: offset_tuning
      }
    end

    # Return string representation of device
    #
    # @return [String] Human-readable device information
    def inspect
      if open?
        "#<RTLSDR::Device:#{object_id.to_s(16)} index=#{@index} name=\"#{name}\" tuner=\"#{tuner_name}\" freq=#{center_freq}Hz rate=#{sample_rate}Hz>" # rubocop:disable Layout/LineLength
      else
        "#<RTLSDR::Device:#{object_id.to_s(16)} index=#{@index} closed>"
      end
    end

    private

    # Open the RTL-SDR device handle
    #
    # @return [void]
    # @raise [DeviceNotFoundError] if device doesn't exist
    # @raise [DeviceOpenError] if device cannot be opened
    # @private
    def open_device
      dev_ptr = ::FFI::MemoryPointer.new(:pointer)
      result = FFI.rtlsdr_open(dev_ptr, @index)

      case result
      when 0
        @handle = dev_ptr.read_pointer
      when -1
        raise DeviceNotFoundError, "Device #{@index} not found"
      when -2
        raise DeviceOpenError, "Device #{@index} already in use"
      when -3
        raise DeviceOpenError, "Device #{@index} cannot be opened"
      else
        raise DeviceOpenError, "Failed to open device #{@index}: error #{result}"
      end
    end

    # Check FFI function result and raise appropriate error
    #
    # @param [Integer] result Return code from FFI function
    # @param [String] message Error message prefix
    # @return [void]
    # @raise [DeviceNotOpenError, InvalidArgumentError, EEPROMError, OperationFailedError]
    # @private
    def check_result(result, message)
      return if result.zero?

      error_msg = "#{message}: error #{result}"
      case result
      when -1 then raise DeviceNotOpenError, error_msg
      when -2 then raise InvalidArgumentError, error_msg
      when -3 then raise EEPROMError, error_msg
      else raise OperationFailedError, error_msg
      end
    end
  end
end
