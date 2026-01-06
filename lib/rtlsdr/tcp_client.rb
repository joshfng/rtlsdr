# frozen_string_literal: true

require "socket"

module RTLSDR
  # TCP client for connecting to rtl_tcp servers
  #
  # TcpClient provides a network interface to RTL-SDR devices that are shared
  # over the network using the rtl_tcp utility. It implements the same interface
  # as RTLSDR::Device, allowing seamless switching between local and remote
  # devices.
  #
  # rtl_tcp is a utility that makes RTL-SDR devices available over TCP/IP.
  # Run it on a remote machine with: rtl_tcp -a 0.0.0.0
  #
  # @example Connect to remote device
  #   device = RTLSDR.connect("192.168.1.100", 1234)
  #   device.sample_rate = 2_048_000
  #   device.center_freq = 100_000_000
  #   device.gain = 400
  #   samples = device.read_samples(1024)
  #   device.close
  #
  # @example Using configure method
  #   device = RTLSDR.connect("localhost")
  #   device.configure(
  #     frequency: 100_000_000,
  #     sample_rate: 2_048_000,
  #     gain: 400
  #   )
  #
  # @since 0.3.0
  class TcpClient
    include Enumerable

    # rtl_tcp command codes
    CMD_SET_FREQUENCY       = 0x01
    CMD_SET_SAMPLE_RATE     = 0x02
    CMD_SET_GAIN_MODE       = 0x03
    CMD_SET_GAIN            = 0x04
    CMD_SET_FREQ_CORRECTION = 0x05
    CMD_SET_IF_GAIN         = 0x06
    CMD_SET_TEST_MODE       = 0x07
    CMD_SET_AGC_MODE        = 0x08
    CMD_SET_DIRECT_SAMPLING = 0x09
    CMD_SET_OFFSET_TUNING   = 0x0a
    CMD_SET_RTL_XTAL        = 0x0b
    CMD_SET_TUNER_XTAL      = 0x0c
    CMD_SET_GAIN_BY_INDEX   = 0x0d
    CMD_SET_BIAS_TEE        = 0x0e

    # Default rtl_tcp port
    DEFAULT_PORT = 1234

    # @return [String] Remote host address
    attr_reader :host
    # @return [Integer] Remote port number
    attr_reader :port
    # @return [Integer] Tuner type from server
    attr_reader :tuner_type
    # @return [Integer] Number of gain values supported
    attr_reader :gain_count

    # Create a new TCP client connection to an rtl_tcp server
    #
    # @param host [String] Hostname or IP address of rtl_tcp server
    # @param port [Integer] Port number (default: 1234)
    # @param timeout [Integer] Connection timeout in seconds (default: 10)
    # @raise [ConnectionError] if connection fails
    # @raise [ConnectionError] if server sends invalid header
    def initialize(host, port = DEFAULT_PORT, timeout: 10)
      @host = host
      @port = port
      @timeout = timeout
      @socket = nil
      @streaming = false
      @mutex = Mutex.new

      # Cached configuration values (rtl_tcp doesn't support reading back)
      @center_freq = 0
      @sample_rate = 0
      @tuner_gain = 0
      @freq_correction = 0
      @direct_sampling = 0
      @offset_tuning = false
      @agc_mode = false
      @test_mode = false
      @gain_mode_manual = false

      connect_to_server
    end

    # Check if connected to server
    #
    # @return [Boolean] true if connected
    def open?
      !@socket.nil? && !@socket.closed?
    end

    # Close the connection
    #
    # @return [void]
    def close
      return unless open?

      @streaming = false
      @socket.close
      @socket = nil
    end

    # Check if connection is closed
    #
    # @return [Boolean] true if closed
    def closed?
      !open?
    end

    # Device information
    def name
      "rtl_tcp://#{@host}:#{@port}"
    end

    # Get USB device strings (not available via TCP)
    #
    # @return [Hash] Hash with placeholder values
    def usb_strings
      {
        manufacturer: "rtl_tcp",
        product: "Remote RTL-SDR",
        serial: "#{@host}:#{@port}"
      }
    end

    # Get human-readable tuner name
    #
    # @return [String] Tuner name based on type code
    def tuner_name
      case @tuner_type
      when 1 then "Elonics E4000"
      when 2 then "Fitipower FC0012"
      when 3 then "Fitipower FC0013"
      when 4 then "FCI FC2580"
      when 5 then "Rafael Micro R820T"
      when 6 then "Rafael Micro R828D"
      else "Unknown"
      end
    end

    # Frequency control

    # Set center frequency
    #
    # @param freq [Integer] Frequency in Hz
    def center_freq=(freq)
      send_command(CMD_SET_FREQUENCY, freq)
      @center_freq = freq
    end

    # Get center frequency
    #
    # @return [Integer] Last set frequency in Hz
    attr_reader :center_freq

    alias frequency center_freq
    alias frequency= center_freq=

    # Set frequency correction in PPM
    #
    # @param ppm [Integer] Frequency correction in parts per million
    def freq_correction=(ppm)
      send_command(CMD_SET_FREQ_CORRECTION, ppm)
      @freq_correction = ppm
    end

    # Get frequency correction
    #
    # @return [Integer] Last set frequency correction in PPM
    attr_reader :freq_correction

    # Crystal oscillator frequencies (not fully supported via TCP)
    def set_xtal_freq(rtl_freq, tuner_freq)
      send_command(CMD_SET_RTL_XTAL, rtl_freq)
      send_command(CMD_SET_TUNER_XTAL, tuner_freq)
      [rtl_freq, tuner_freq]
    end

    # Get crystal frequencies (returns zeros - not readable via TCP)
    #
    # @return [Array<Integer>] Array of [0, 0]
    def xtal_freq
      [0, 0]
    end

    # Gain control

    # Get available tuner gains (not queryable via TCP, returns common values)
    #
    # @return [Array<Integer>] Common R820T gain values in tenths of dB
    def tuner_gains
      # Return common R820T gains as a reasonable default
      [0, 9, 14, 27, 37, 77, 87, 125, 144, 157, 166, 197, 207, 229, 254,
       280, 297, 328, 338, 364, 372, 386, 402, 421, 434, 439, 445, 480, 496]
    end

    # Set tuner gain in tenths of dB
    #
    # @param gain [Integer] Gain in tenths of dB (e.g., 496 = 49.6 dB)
    def tuner_gain=(gain)
      send_command(CMD_SET_GAIN, gain)
      @tuner_gain = gain
    end

    # Get current tuner gain
    #
    # @return [Integer] Last set gain in tenths of dB
    attr_reader :tuner_gain

    alias gain tuner_gain
    alias gain= tuner_gain=

    # Set gain mode (manual or automatic)
    #
    # @param manual [Boolean] true for manual, false for automatic
    def tuner_gain_mode=(manual)
      mode = manual ? 1 : 0
      send_command(CMD_SET_GAIN_MODE, mode)
      @gain_mode_manual = manual
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
    # @param stage [Integer] IF stage number
    # @param gain [Integer] Gain value in tenths of dB
    # @return [Integer] The gain value that was set
    def set_tuner_if_gain(stage, gain)
      param = (stage << 16) | (gain & 0xFFFF)
      send_command(CMD_SET_IF_GAIN, param)
      gain
    end

    # Set tuner bandwidth (not supported via rtl_tcp)
    #
    # @param _bw [Integer] Bandwidth in Hz (ignored)
    def tuner_bandwidth=(_bw)
      # rtl_tcp doesn't support bandwidth command
    end

    # Sample rate control

    # Set sample rate
    #
    # @param rate [Integer] Sample rate in Hz
    def sample_rate=(rate)
      send_command(CMD_SET_SAMPLE_RATE, rate)
      @sample_rate = rate
    end

    # Get current sample rate
    #
    # @return [Integer] Last set sample rate in Hz
    attr_reader :sample_rate

    alias samp_rate sample_rate
    alias samp_rate= sample_rate=

    # Mode control

    # Set test mode
    #
    # @param enabled [Boolean] true to enable test mode
    def test_mode=(enabled)
      mode = enabled ? 1 : 0
      send_command(CMD_SET_TEST_MODE, mode)
      @test_mode = enabled
    end

    # Enable test mode
    #
    # @return [Boolean] true
    def test_mode!
      self.test_mode = true
    end

    # Set AGC mode
    #
    # @param enabled [Boolean] true to enable AGC
    def agc_mode=(enabled)
      mode = enabled ? 1 : 0
      send_command(CMD_SET_AGC_MODE, mode)
      @agc_mode = enabled
    end

    # Enable AGC mode
    #
    # @return [Boolean] true
    def agc_mode!
      self.agc_mode = true
    end

    # Set direct sampling mode
    #
    # @param mode [Integer] Direct sampling mode (0=off, 1=I-ADC, 2=Q-ADC)
    def direct_sampling=(mode)
      send_command(CMD_SET_DIRECT_SAMPLING, mode)
      @direct_sampling = mode
    end

    # Get direct sampling mode
    #
    # @return [Integer] Last set direct sampling mode
    attr_reader :direct_sampling

    # Set offset tuning mode
    #
    # @param enabled [Boolean] true to enable offset tuning
    def offset_tuning=(enabled)
      mode = enabled ? 1 : 0
      send_command(CMD_SET_OFFSET_TUNING, mode)
      @offset_tuning = enabled
    end

    # Get offset tuning mode
    #
    # @return [Boolean] Last set offset tuning state
    attr_reader :offset_tuning

    # Enable offset tuning
    #
    # @return [Boolean] true
    def offset_tuning!
      self.offset_tuning = true
    end

    # Bias tee control

    # Set bias tee state
    #
    # @param enabled [Boolean] true to enable bias tee
    def bias_tee=(enabled)
      mode = enabled ? 1 : 0
      send_command(CMD_SET_BIAS_TEE, mode)
    end

    # Enable bias tee
    #
    # @return [Boolean] true
    def enable_bias_tee
      self.bias_tee = true
    end

    # Disable bias tee
    #
    # @return [Boolean] false
    def disable_bias_tee
      self.bias_tee = false
    end

    # Enable bias tee (alias)
    #
    # @return [Boolean] true
    def bias_tee!
      enable_bias_tee
    end

    # Bias tee GPIO not supported via TCP
    def set_bias_tee_gpio(_gpio, enabled)
      self.bias_tee = enabled
    end

    # EEPROM not accessible via TCP

    # Read EEPROM (not supported via TCP)
    #
    # @raise [OperationFailedError] always
    def read_eeprom(_offset, _length)
      raise OperationFailedError, "EEPROM access not supported via TCP"
    end

    # Write EEPROM (not supported via TCP)
    #
    # @raise [OperationFailedError] always
    def write_eeprom(_data, _offset)
      raise OperationFailedError, "EEPROM access not supported via TCP"
    end

    # Dump EEPROM (not supported via TCP)
    #
    # @raise [OperationFailedError] always
    def dump_eeprom
      raise OperationFailedError, "EEPROM access not supported via TCP"
    end

    # Buffer reset (no-op for TCP)
    def reset_buffer
      # rtl_tcp doesn't have a reset buffer command
      # Data is continuously streamed
    end

    # Read raw IQ data synchronously
    #
    # @param length [Integer] Number of bytes to read
    # @return [Array<Integer>] Array of 8-bit unsigned integers
    # @raise [ConnectionError] if read fails
    def read_sync(length)
      raise ConnectionError, "Not connected" unless open?

      data = +""
      remaining = length

      while remaining.positive?
        chunk = @socket.read(remaining)
        raise ConnectionError, "Connection closed by server" if chunk.nil? || chunk.empty?

        data << chunk
        remaining -= chunk.bytesize
      end

      data.unpack("C*")
    end

    # Read complex samples synchronously
    #
    # @param count [Integer] Number of complex samples to read
    # @return [Array<Complex>] Array of complex samples
    def read_samples(count = 1024)
      # RTL-SDR outputs 8-bit I/Q samples, so we need 2 bytes per complex sample
      data = read_sync(count * 2)

      # Convert to complex numbers (I + jQ)
      samples = []
      (0...data.length).step(2) do |i|
        i_sample = (data[i] - 128) / 128.0
        q_sample = (data[i + 1] - 128) / 128.0
        samples << Complex(i_sample, q_sample)
      end

      samples
    end

    # Check if streaming
    #
    # @return [Boolean] true if streaming
    def streaming?
      @streaming
    end

    # Read raw IQ data asynchronously
    #
    # @param buffer_count [Integer] Ignored for TCP
    # @param buffer_length [Integer] Buffer size in bytes
    # @yield [Array<Integer>] Block called with each buffer
    # @return [Thread] Background reading thread
    def read_async(buffer_count: 15, buffer_length: 262_144, &block)
      raise ArgumentError, "Block required for async reading" unless block_given?
      raise OperationFailedError, "Already streaming" if streaming?

      _ = buffer_count # unused for TCP
      @streaming = true

      Thread.new do
        while @streaming && open?
          begin
            data = read_sync(buffer_length)
            block.call(data)
          rescue ConnectionError => e
            @streaming = false
            raise e unless e.message.include?("closed")
          rescue StandardError => e
            puts "Error in async callback: #{e.message}"
            @streaming = false
          end
        end
      end
    end

    # Read complex samples asynchronously
    #
    # @param buffer_count [Integer] Ignored for TCP
    # @param buffer_length [Integer] Buffer size in bytes
    # @yield [Array<Complex>] Block called with complex samples
    # @return [Thread] Background reading thread
    def read_samples_async(buffer_count: 15, buffer_length: 262_144, &block)
      raise ArgumentError, "Block required for async reading" unless block_given?

      read_async(buffer_count: buffer_count, buffer_length: buffer_length) do |data|
        samples = []
        (0...data.length).step(2) do |i|
          i_sample = (data[i] - 128) / 128.0
          q_sample = (data[i + 1] - 128) / 128.0
          samples << Complex(i_sample, q_sample)
        end

        block.call(samples)
      end
    end

    # Cancel asynchronous reading
    #
    # @return [void]
    def cancel_async
      @streaming = false
    end

    # Enumerable interface
    def each(samples_per_read: 1024)
      return enum_for(:each, samples_per_read: samples_per_read) unless block_given?

      loop do
        samples = read_samples(samples_per_read)
        yield samples
      rescue StandardError => e
        break if e.is_a?(Interrupt) || e.is_a?(ConnectionError)

        raise
      end
    end

    # Configuration shortcut
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
        host: @host,
        port: @port,
        name: name,
        usb_strings: usb_strings,
        tuner_type: @tuner_type,
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

    # String representation
    def inspect
      if open?
        "#<RTLSDR::TcpClient:#{object_id.to_s(16)} #{name} tuner=\"#{tuner_name}\" " \
          "freq=#{center_freq}Hz rate=#{sample_rate}Hz>"
      else
        "#<RTLSDR::TcpClient:#{object_id.to_s(16)} #{name} closed>"
      end
    end

    private

    # Connect to rtl_tcp server and read header
    #
    # @raise [ConnectionError] if connection or header validation fails
    def connect_to_server
      @socket = Socket.tcp(@host, @port, connect_timeout: @timeout)
      @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      # Read 12-byte header: "RTL0" + tuner_type(4) + gain_count(4)
      header = @socket.read(12)
      raise ConnectionError, "Failed to read header from rtl_tcp server" if header.nil? || header.length < 12

      magic = header[0, 4]
      raise ConnectionError, "Invalid rtl_tcp header magic: expected 'RTL0', got '#{magic}'" unless magic == "RTL0"

      @tuner_type = header[4, 4].unpack1("N")
      @gain_count = header[8, 4].unpack1("N")
    rescue Errno::ECONNREFUSED
      raise ConnectionError, "Connection refused to #{@host}:#{@port} - is rtl_tcp running?"
    rescue Errno::ETIMEDOUT, Errno::EHOSTUNREACH => e
      raise ConnectionError, "Cannot reach #{@host}:#{@port}: #{e.message}"
    rescue SocketError => e
      raise ConnectionError, "Socket error connecting to #{@host}:#{@port}: #{e.message}"
    end

    # Send a command to the rtl_tcp server
    #
    # @param cmd [Integer] Command code
    # @param param [Integer] Command parameter
    # @raise [ConnectionError] if send fails
    def send_command(cmd, param)
      raise ConnectionError, "Not connected" unless open?

      # Command is 5 bytes: 1 byte command + 4 bytes big-endian parameter
      packet = [cmd, param].pack("CN")
      @mutex.synchronize do
        @socket.write(packet)
      end
    rescue Errno::EPIPE, Errno::ECONNRESET => e
      @socket = nil
      raise ConnectionError, "Connection lost: #{e.message}"
    end
  end
end
