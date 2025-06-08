# frozen_string_literal: true

module RTLSDR
  # Digital Signal Processing utilities for RTL-SDR
  #
  # The DSP module provides essential signal processing functions for working
  # with RTL-SDR sample data. It includes utilities for converting raw IQ data
  # to complex samples, calculating power spectra, performing filtering
  # operations, and extracting signal characteristics.
  #
  # All methods are designed to work with Ruby's Complex number type and
  # standard Array collections, making them easy to integrate into Ruby
  # applications and pipelines.
  #
  # Features:
  # * IQ data conversion to complex samples
  # * Power spectrum analysis with windowing
  # * Peak detection and frequency estimation
  # * DC removal and filtering
  # * Magnitude and phase extraction
  # * Average power calculation
  #
  # @example Basic signal analysis
  #   raw_data = device.read_sync(2048)
  #   samples = RTLSDR::DSP.iq_to_complex(raw_data)
  #   power = RTLSDR::DSP.average_power(samples)
  #   spectrum = RTLSDR::DSP.power_spectrum(samples)
  #   peak_idx, peak_power = RTLSDR::DSP.find_peak(spectrum)
  #
  # @example Signal conditioning
  #   filtered = RTLSDR::DSP.remove_dc(samples)
  #   magnitudes = RTLSDR::DSP.magnitude(filtered)
  #   phases = RTLSDR::DSP.phase(filtered)
  module DSP
    # Convert raw IQ data to complex samples
    #
    # Converts raw 8-bit IQ data from RTL-SDR devices to Ruby Complex numbers.
    # The RTL-SDR outputs unsigned 8-bit integers centered at 128, which are
    # converted to floating point values in the range [-1.0, 1.0].
    #
    # @param [Array<Integer>] data Array of 8-bit unsigned integers (I, Q, I, Q, ...)
    # @return [Array<Complex>] Array of Complex numbers representing I+jQ samples
    # @example Convert device samples
    #   raw_data = [127, 130, 125, 135, 120, 140]  # 3 IQ pairs
    #   samples = RTLSDR::DSP.iq_to_complex(raw_data)
    #   # => [(-0.008+0.016i), (-0.024+0.055i), (-0.063+0.094i)]
    def self.iq_to_complex(data)
      samples = []
      (0...data.length).step(2) do |i|
        i_sample = (data[i] - 128) / 128.0
        q_sample = (data[i + 1] - 128) / 128.0
        samples << Complex(i_sample, q_sample)
      end
      samples
    end

    # Calculate power spectral density
    #
    # Computes a basic power spectrum from complex samples using windowing.
    # This applies a Hanning window to reduce spectral leakage and then
    # calculates the power (magnitude squared) for each sample. A proper
    # FFT implementation would require an external library.
    #
    # @param [Array<Complex>] samples Array of complex samples
    # @param [Integer] window_size Size of the analysis window (default 1024)
    # @return [Array<Float>] Power spectrum values
    # @example Calculate spectrum
    #   spectrum = RTLSDR::DSP.power_spectrum(samples, 512)
    #   max_power = spectrum.max
    def self.power_spectrum(samples, window_size = 1024)
      return [] if samples.length < window_size

      windowed_samples = samples.take(window_size)

      # Apply Hanning window
      windowed_samples = windowed_samples.each_with_index.map do |sample, i|
        window_factor = 0.5 * (1 - Math.cos(2 * Math::PI * i / (window_size - 1)))
        sample * window_factor
      end

      # Simple magnitude calculation (real FFT would require external library)
      windowed_samples.map { |s| ((s.real**2) + (s.imag**2)) }
    end

    # Calculate average power of complex samples
    #
    # Computes the mean power (magnitude squared) across all samples.
    # This is useful for signal strength measurements and AGC calculations.
    #
    # @param [Array<Complex>] samples Array of complex samples
    # @return [Float] Average power value (0.0 if no samples)
    # @example Measure signal power
    #   power = RTLSDR::DSP.average_power(samples)
    #   power_db = 10 * Math.log10(power + 1e-10)
    def self.average_power(samples)
      return 0.0 if samples.empty?

      total_power = samples.reduce(0.0) { |sum, sample| sum + sample.abs2 }
      total_power / samples.length
    end

    # Find peak power and frequency bin in spectrum
    #
    # Locates the frequency bin with maximum power in a power spectrum.
    # Returns both the bin index and the power value at that bin.
    #
    # @param [Array<Float>] power_spectrum Array of power values
    # @return [Array<Integer, Float>] [bin_index, peak_power] or [0, 0.0] if empty
    # @example Find strongest signal
    #   spectrum = RTLSDR::DSP.power_spectrum(samples)
    #   peak_bin, peak_power = RTLSDR::DSP.find_peak(spectrum)
    #   freq_offset = (peak_bin - spectrum.length/2) * sample_rate / spectrum.length
    def self.find_peak(power_spectrum)
      return [0, 0.0] if power_spectrum.empty?

      max_power = power_spectrum.max
      max_index = power_spectrum.index(max_power)
      [max_index, max_power]
    end

    # Remove DC component using high-pass filter
    #
    # Applies a simple first-order high-pass filter to remove DC bias
    # from the signal. This is useful for RTL-SDR devices which often
    # have a DC offset in their I/Q samples.
    #
    # @param [Array<Complex>] samples Array of complex samples
    # @param [Float] alpha Filter coefficient (0.995 = ~160Hz cutoff at 2.4MHz sample rate)
    # @return [Array<Complex>] Filtered samples with DC component removed
    # @example Remove DC bias
    #   clean_samples = RTLSDR::DSP.remove_dc(samples, 0.99)
    def self.remove_dc(samples, alpha = 0.995)
      return samples if samples.empty?

      filtered = [samples.first]
      (1...samples.length).each do |i|
        filtered[i] = samples[i] - samples[i - 1] + (alpha * filtered[i - 1])
      end
      filtered
    end

    # Extract magnitude from complex samples
    #
    # Calculates the magnitude (absolute value) of each complex sample.
    # This converts I+jQ samples to their envelope/amplitude values.
    #
    # @param [Array<Complex>] samples Array of complex samples
    # @return [Array<Float>] Array of magnitude values
    # @example Get signal envelope
    #   magnitudes = RTLSDR::DSP.magnitude(samples)
    #   peak_amplitude = magnitudes.max
    def self.magnitude(samples)
      samples.map(&:abs)
    end

    # Extract phase from complex samples
    #
    # Calculates the phase angle (argument) of each complex sample in radians.
    # The phase represents the angle between the I and Q components.
    #
    # @param [Array<Complex>] samples Array of complex samples
    # @return [Array<Float>] Array of phase values in radians (-π to π)
    # @example Get phase information
    #   phases = RTLSDR::DSP.phase(samples)
    #   phase_degrees = phases.map { |p| p * 180 / Math::PI }
    def self.phase(samples)
      samples.map { |s| Math.atan2(s.imag, s.real) }
    end

    # Estimate frequency using zero-crossing detection
    #
    # Provides a rough frequency estimate by counting zero crossings in the
    # magnitude signal. This is a simple method that works reasonably well
    # for single-tone signals but may be inaccurate for complex signals.
    #
    # @param [Array<Complex>] samples Array of complex samples
    # @param [Integer] sample_rate Sample rate in Hz
    # @return [Float] Estimated frequency in Hz
    # @example Estimate carrier frequency
    #   freq_hz = RTLSDR::DSP.estimate_frequency(samples, 2_048_000)
    #   puts "Estimated frequency: #{freq_hz} Hz"
    def self.estimate_frequency(samples, sample_rate)
      return 0.0 if samples.length < 2

      magnitudes = magnitude(samples)
      zero_crossings = 0

      (1...magnitudes.length).each do |i|
        if (magnitudes[i - 1] >= 0 && magnitudes[i].negative?) ||
           (magnitudes[i - 1].negative? && magnitudes[i] >= 0)
          zero_crossings += 1
        end
      end

      # Frequency = (zero crossings / 2) / time_duration
      time_duration = samples.length.to_f / sample_rate
      (zero_crossings / 2.0) / time_duration
    end
  end
end
