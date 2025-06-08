# frozen_string_literal: true

module RTLSDR
  # Frequency scanning and spectrum analysis
  #
  # The Scanner class provides high-level frequency scanning capabilities for
  # RTL-SDR devices. It automates the process of sweeping across frequency
  # ranges, collecting samples, and analyzing signal characteristics. This is
  # particularly useful for spectrum analysis, signal hunting, and surveillance
  # applications.
  #
  # Features:
  # * Configurable frequency range and step size
  # * Adjustable dwell time per frequency
  # * Synchronous and asynchronous scanning modes
  # * Peak detection with power thresholds
  # * Power sweep analysis
  # * Real-time result callbacks
  # * Thread-safe scanning control
  #
  # @example Basic frequency scan
  #   scanner = RTLSDR::Scanner.new(
  #     device,
  #     start_freq: 88_000_000,    # 88 MHz
  #     end_freq: 108_000_000,     # 108 MHz
  #     step_size: 100_000,        # 100 kHz steps
  #     dwell_time: 0.1            # 100ms per frequency
  #   )
  #
  #   scanner.scan do |result|
  #     puts "#{result[:frequency] / 1e6} MHz: #{result[:power]} dBm"
  #   end
  #
  # @example Find strong signals
  #   peaks = scanner.find_peaks(threshold: -60)
  #   peaks.each do |peak|
  #     puts "Strong signal at #{peak[:frequency] / 1e6} MHz"
  #   end
  class Scanner
    # @return [RTLSDR::Device] The RTL-SDR device being used for scanning
    attr_reader :device
    # @return [Integer] Starting frequency in Hz
    attr_reader :start_freq
    # @return [Integer] Ending frequency in Hz
    attr_reader :end_freq
    # @return [Integer] Frequency step size in Hz
    attr_reader :step_size
    # @return [Float] Time to dwell on each frequency in seconds
    attr_reader :dwell_time

    # Create a new frequency scanner
    #
    # @param [RTLSDR::Device] device RTL-SDR device to use for scanning
    # @param [Integer] start_freq Starting frequency in Hz
    # @param [Integer] end_freq Ending frequency in Hz
    # @param [Integer] step_size Frequency step size in Hz (default: 1 MHz)
    # @param [Float] dwell_time Time to spend on each frequency in seconds (default: 0.1s)
    # @example Create FM band scanner
    #   scanner = RTLSDR::Scanner.new(
    #     device,
    #     start_freq: 88_000_000,    # 88 MHz
    #     end_freq: 108_000_000,     # 108 MHz
    #     step_size: 200_000,        # 200 kHz
    #     dwell_time: 0.05           # 50ms per frequency
    #   )
    def initialize(device, start_freq:, end_freq:, step_size: 1_000_000, dwell_time: 0.1)
      @device = device
      @start_freq = start_freq
      @end_freq = end_freq
      @step_size = step_size
      @dwell_time = dwell_time
      @scanning = false
    end

    # Get array of all frequencies to be scanned
    #
    # @return [Array<Integer>] Array of frequencies in Hz
    # @example Get frequency list
    #   freqs = scanner.frequencies
    #   puts "Will scan #{freqs.length} frequencies"
    def frequencies
      (@start_freq..@end_freq).step(@step_size).to_a
    end

    # Get total number of frequencies to be scanned
    #
    # @return [Integer] Number of frequency steps
    def frequency_count
      ((end_freq - start_freq) / step_size).to_i + 1
    end

    # Perform a frequency sweep scan
    #
    # Scans through all frequencies in the configured range, collecting samples
    # and calling the provided block for each frequency. The block receives a
    # hash with frequency, power, samples, and timestamp information.
    #
    # @param [Integer] samples_per_freq Number of samples to collect per frequency
    # @yield [Hash] Block called for each frequency with scan results
    # @yieldparam result [Hash] Scan result containing :frequency, :power, :samples, :timestamp
    # @return [Hash] Hash of all results keyed by frequency
    # @example Scan and log results
    #   results = scanner.scan(samples_per_freq: 2048) do |result|
    #     power_db = 10 * Math.log10(result[:power] + 1e-10)
    #     puts "#{result[:frequency]/1e6} MHz: #{power_db.round(1)} dB"
    #   end
    def scan(samples_per_freq: 1024, &block)
      raise ArgumentError, "Block required for scan" unless block_given?

      @scanning = true
      results = {}

      frequencies.each do |freq|
        break unless @scanning

        @device.center_freq = freq
        sleep(@dwell_time)

        samples = @device.read_samples(samples_per_freq)
        power = DSP.average_power(samples)

        result = {
          frequency: freq,
          power: power,
          samples: samples,
          timestamp: Time.now
        }

        results[freq] = result
        block.call(result)
      end

      @scanning = false
      results
    end

    # Perform asynchronous frequency sweep scan
    #
    # Same as {#scan} but runs in a separate thread, allowing the calling
    # thread to continue execution while scanning proceeds in the background.
    #
    # @param [Integer] samples_per_freq Number of samples to collect per frequency
    # @yield [Hash] Block called for each frequency with scan results
    # @return [Thread] Thread object running the scan
    # @example Background scanning
    #   scan_thread = scanner.scan_async do |result|
    #     # Process results in background
    #   end
    #   # Do other work...
    #   scan_thread.join  # Wait for completion
    def scan_async(samples_per_freq: 1024, &block)
      raise ArgumentError, "Block required for async scan" unless block_given?

      Thread.new do
        scan(samples_per_freq: samples_per_freq, &block)
      end
    end

    # Find signal peaks above a power threshold
    #
    # Scans the frequency range and returns all frequencies where the signal
    # power exceeds the specified threshold. Results are sorted by power
    # in descending order (strongest signals first).
    #
    # @param [Float] threshold Power threshold in dB (default: -60 dB)
    # @param [Integer] samples_per_freq Number of samples per frequency
    # @return [Array<Hash>] Array of peak information hashes
    # @example Find strong signals
    #   peaks = scanner.find_peaks(threshold: -50, samples_per_freq: 4096)
    #   peaks.each do |peak|
    #     puts "#{peak[:frequency]/1e6} MHz: #{peak[:power_db]} dB"
    #   end
    def find_peaks(threshold: -60, samples_per_freq: 1024)
      peaks = []

      scan(samples_per_freq: samples_per_freq) do |result|
        power_db = 10 * Math.log10(result[:power] + 1e-10)
        if power_db > threshold
          peaks << {
            frequency: result[:frequency],
            power: result[:power],
            power_db: power_db,
            timestamp: result[:timestamp]
          }
        end
      end

      peaks.sort_by { |peak| -peak[:power] }
    end

    # Perform a power sweep across the frequency range
    #
    # Scans all frequencies and returns an array of [frequency, power_db] pairs.
    # This is useful for generating spectrum plots or finding the overall
    # power distribution across a frequency band.
    #
    # @param [Integer] samples_per_freq Number of samples per frequency
    # @return [Array<Array>] Array of [frequency_hz, power_db] pairs
    # @example Generate spectrum data
    #   spectrum_data = scanner.power_sweep(samples_per_freq: 2048)
    #   spectrum_data.each do |freq, power|
    #     puts "#{freq/1e6} MHz: #{power.round(1)} dB"
    #   end
    def power_sweep(samples_per_freq: 1024)
      results = []

      scan(samples_per_freq: samples_per_freq) do |result|
        power_db = 10 * Math.log10(result[:power] + 1e-10)
        results << [result[:frequency], power_db]
      end

      results
    end

    # Stop the current scan operation
    #
    # Sets the scanning flag to false, which will cause any active scan
    # to terminate after the current frequency step completes.
    #
    # @return [Boolean] false (new scanning state)
    def stop
      @scanning = false
    end

    # Check if a scan is currently in progress
    #
    # @return [Boolean] true if scanning, false otherwise
    def scanning?
      @scanning
    end

    # Update scan configuration parameters
    #
    # Allows modification of scan parameters after the scanner has been created.
    # Only non-nil parameters will be updated.
    #
    # @param [Integer, nil] start_freq New starting frequency in Hz
    # @param [Integer, nil] end_freq New ending frequency in Hz
    # @param [Integer, nil] step_size New step size in Hz
    # @param [Float, nil] dwell_time New dwell time in seconds
    # @return [Scanner] self for method chaining
    # @example Reconfigure scanner
    #   scanner.configure(start_freq: 400_000_000, step_size: 25_000)
    def configure(start_freq: nil, end_freq: nil, step_size: nil, dwell_time: nil)
      @start_freq = start_freq if start_freq
      @end_freq = end_freq if end_freq
      @step_size = step_size if step_size
      @dwell_time = dwell_time if dwell_time
      self
    end

    # Return string representation of scanner
    #
    # @return [String] Human-readable scanner configuration
    def inspect
      "#<RTLSDR::Scanner #{@start_freq / 1e6}MHz-#{@end_freq / 1e6}MHz step=#{@step_size / 1e6}MHz dwell=#{@dwell_time}s>" # rubocop:disable Layout/LineLength
    end
  end
end
