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
  # * FFT and IFFT via FFTW3 (when available)
  # * Power spectrum analysis with windowing
  # * Peak detection and frequency estimation
  # * DC removal and filtering
  # * Magnitude and phase extraction
  # * Average power calculation
  # * Decimation and resampling
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

    # =========================================================================
    # FFT Methods (require FFTW3)
    # =========================================================================

    # Check if FFT is available (FFTW3 loaded)
    #
    # @return [Boolean] true if FFTW3 is available for FFT operations
    # @example Check FFT availability
    #   if RTLSDR::DSP.fft_available?
    #     spectrum = RTLSDR::DSP.fft(samples)
    #   end
    def self.fft_available?
      defined?(RTLSDR::FFTW) && RTLSDR::FFTW.available?
    end

    # Compute forward FFT of complex samples
    #
    # Performs a Fast Fourier Transform using FFTW3. The result is an array
    # of complex frequency bins from DC to Nyquist to negative frequencies.
    #
    # @param [Array<Complex>] samples Input complex time-domain samples
    # @return [Array<Complex>] Complex frequency-domain bins
    # @raise [RuntimeError] if FFTW3 is not available
    # @example Compute FFT
    #   spectrum = RTLSDR::DSP.fft(samples)
    #   magnitudes = spectrum.map(&:abs)
    def self.fft(samples)
      raise "FFTW3 not available. Install libfftw3." unless fft_available?

      RTLSDR::FFTW.forward(samples)
    end

    # Compute inverse FFT of complex spectrum
    #
    # Performs an Inverse Fast Fourier Transform using FFTW3. Converts
    # frequency-domain data back to time-domain samples.
    #
    # @param [Array<Complex>] spectrum Input complex frequency-domain bins
    # @return [Array<Complex>] Complex time-domain samples
    # @raise [RuntimeError] if FFTW3 is not available
    # @example Reconstruct time domain
    #   reconstructed = RTLSDR::DSP.ifft(spectrum)
    def self.ifft(spectrum)
      raise "FFTW3 not available. Install libfftw3." unless fft_available?

      RTLSDR::FFTW.backward(spectrum)
    end

    # Compute power spectrum in decibels
    #
    # Calculates the power spectrum using FFT and returns values in dB.
    # Applies optional windowing to reduce spectral leakage.
    #
    # @param [Array<Complex>] samples Input complex samples
    # @param [Symbol] window Window type (:hanning, :hamming, :blackman, :none)
    # @return [Array<Float>] Power spectrum in dB
    # @example Get dB spectrum
    #   power_db = RTLSDR::DSP.fft_power_db(samples, window: :hanning)
    def self.fft_power_db(samples, window: :hanning)
      windowed = apply_window(samples, window)
      spectrum = fft(windowed)
      spectrum.map { |s| 10 * Math.log10(s.abs2 + 1e-20) }
    end

    # Shift FFT output to center DC component
    #
    # Rearranges FFT output so that DC (0 Hz) is in the center, with
    # negative frequencies on the left and positive on the right.
    # Similar to numpy.fft.fftshift.
    #
    # @param [Array] spectrum FFT output array
    # @return [Array] Shifted spectrum with DC centered
    # @example Center the spectrum
    #   centered = RTLSDR::DSP.fft_shift(spectrum)
    def self.fft_shift(spectrum)
      n = spectrum.length
      mid = n / 2
      spectrum[mid..] + spectrum[0...mid]
    end

    # Inverse of fft_shift
    #
    # Reverses the fft_shift operation to restore original FFT ordering.
    #
    # @param [Array] spectrum Shifted spectrum
    # @return [Array] Unshifted spectrum
    def self.ifft_shift(spectrum)
      n = spectrum.length
      mid = (n + 1) / 2
      spectrum[mid..] + spectrum[0...mid]
    end

    # Apply window function to samples
    #
    # Applies a window function to reduce spectral leakage in FFT analysis.
    # Supported windows: :hanning, :hamming, :blackman, :none
    #
    # @param [Array<Complex>] samples Input samples
    # @param [Symbol] window_type Window function to apply
    # @return [Array<Complex>] Windowed samples
    # @example Apply Hanning window
    #   windowed = RTLSDR::DSP.apply_window(samples, :hanning)
    def self.apply_window(samples, window_type = :hanning)
      n = samples.length
      return samples if n.zero? || window_type == :none

      samples.each_with_index.map do |sample, i|
        window = case window_type
                 when :hanning
                   0.5 * (1 - Math.cos(2 * Math::PI * i / (n - 1)))
                 when :hamming
                   0.54 - (0.46 * Math.cos(2 * Math::PI * i / (n - 1)))
                 when :blackman
                   0.42 - (0.5 * Math.cos(2 * Math::PI * i / (n - 1))) +
                   (0.08 * Math.cos(4 * Math::PI * i / (n - 1)))
                 else
                   1.0
                 end
        sample * window
      end
    end

    # =========================================================================
    # Decimation and Resampling
    # =========================================================================

    # Decimate samples by an integer factor
    #
    # Reduces the sample rate by applying a lowpass anti-aliasing filter
    # and then downsampling. The cutoff frequency is automatically set
    # to prevent aliasing.
    #
    # @param [Array<Complex>] samples Input samples
    # @param [Integer] factor Decimation factor (must be >= 1)
    # @param [Integer] filter_taps Number of filter taps (more = sharper rolloff)
    # @return [Array<Complex>] Decimated samples
    # @example Decimate by 4
    #   decimated = RTLSDR::DSP.decimate(samples, 4)
    def self.decimate(samples, factor, filter_taps: 31)
      return samples if factor <= 1

      # Design lowpass filter with cutoff at 0.5/factor of Nyquist
      cutoff = 0.5 / factor
      filter = design_lowpass(cutoff, filter_taps)

      # Apply filter
      filtered = convolve(samples, filter)

      # Downsample
      result = []
      (0...filtered.length).step(factor) { |i| result << filtered[i] }
      result
    end

    # Interpolate samples by an integer factor
    #
    # Increases the sample rate by inserting zeros and then applying
    # a lowpass interpolation filter.
    #
    # @param [Array<Complex>] samples Input samples
    # @param [Integer] factor Interpolation factor (must be >= 1)
    # @param [Integer] filter_taps Number of filter taps
    # @return [Array<Complex>] Interpolated samples
    # @example Interpolate by 2
    #   interpolated = RTLSDR::DSP.interpolate(samples, 2)
    def self.interpolate(samples, factor, filter_taps: 31)
      return samples if factor <= 1

      # Insert zeros (upsample)
      upsampled = []
      samples.each do |sample|
        upsampled << sample
        (factor - 1).times { upsampled << Complex(0, 0) }
      end

      # Design lowpass filter
      cutoff = 0.5 / factor
      filter = design_lowpass(cutoff, filter_taps)

      # Apply filter and scale
      filtered = convolve(upsampled, filter)
      filtered.map { |s| s * factor }
    end

    # Resample to a new sample rate using rational resampling
    #
    # Resamples by first interpolating then decimating. The interpolation
    # and decimation factors are determined by the ratio of sample rates.
    #
    # @param [Array<Complex>] samples Input samples
    # @param [Integer] from_rate Original sample rate in Hz
    # @param [Integer] to_rate Target sample rate in Hz
    # @param [Integer] filter_taps Number of filter taps
    # @return [Array<Complex>] Resampled samples
    # @example Resample from 2.4 MHz to 48 kHz
    #   resampled = RTLSDR::DSP.resample(samples, from_rate: 2_400_000, to_rate: 48_000)
    def self.resample(samples, from_rate:, to_rate:, filter_taps: 31)
      return samples if from_rate == to_rate

      # Find GCD to minimize interpolation/decimation factors
      gcd = from_rate.gcd(to_rate)
      interp_factor = to_rate / gcd
      decim_factor = from_rate / gcd

      # Limit factors to reasonable values
      max_factor = 100
      if interp_factor > max_factor || decim_factor > max_factor
        # Fall back to simple linear interpolation for large ratios
        return linear_resample(samples, from_rate, to_rate)
      end

      # Interpolate then decimate
      result = samples
      result = interpolate(result, interp_factor, filter_taps: filter_taps) if interp_factor > 1
      result = decimate(result, decim_factor, filter_taps: filter_taps) if decim_factor > 1
      result
    end

    # Design a lowpass FIR filter using windowed sinc
    #
    # @param [Float] cutoff Normalized cutoff frequency (0 to 0.5)
    # @param [Integer] taps Number of filter taps (should be odd)
    # @return [Array<Float>] Filter coefficients
    def self.design_lowpass(cutoff, taps = 31)
      # Ensure odd number of taps for symmetry
      taps += 1 unless taps.odd?
      mid = (taps - 1) / 2.0

      coeffs = Array.new(taps) do |n|
        m = n - mid
        # Sinc function
        sinc = if m.zero?
                 2 * cutoff
               else
                 Math.sin(2 * Math::PI * cutoff * m) / (Math::PI * m)
               end
        # Hamming window
        window = 0.54 - (0.46 * Math.cos(2 * Math::PI * n / (taps - 1)))
        sinc * window
      end

      # Normalize to unity gain at DC
      sum = coeffs.sum
      coeffs.map { |c| c / sum }
    end

    # Convolve samples with filter coefficients
    #
    # @param [Array<Complex>] samples Input samples
    # @param [Array<Float>] filter Filter coefficients
    # @return [Array<Complex>] Filtered samples
    def self.convolve(samples, filter)
      return samples if filter.empty?

      n = samples.length
      m = filter.length
      result = Array.new(n, Complex(0, 0))

      n.times do |i|
        sum = Complex(0, 0)
        m.times do |j|
          k = i - j + (m / 2)
          sum += samples[k] * filter[j] if k >= 0 && k < n
        end
        result[i] = sum
      end

      result
    end

    private_class_method :design_lowpass, :convolve

    # Simple linear interpolation for large resampling ratios
    #
    # @param [Array<Complex>] samples Input samples
    # @param [Integer] from_rate Original sample rate
    # @param [Integer] to_rate Target sample rate
    # @return [Array<Complex>] Resampled samples
    def self.linear_resample(samples, from_rate, to_rate)
      return samples if samples.empty?

      ratio = from_rate.to_f / to_rate
      output_length = (samples.length / ratio).to_i
      return samples if output_length <= 0

      Array.new(output_length) do |i|
        pos = i * ratio
        idx = pos.to_i
        frac = pos - idx

        if idx + 1 < samples.length
          (samples[idx] * (1 - frac)) + (samples[idx + 1] * frac)
        else
          samples[idx] || Complex(0, 0)
        end
      end
    end

    private_class_method :linear_resample
  end
end
