# frozen_string_literal: true

module RTLSDR
  module DSP
    # FIR (Finite Impulse Response) filter class
    #
    # Provides methods for designing and applying FIR filters to complex
    # or real-valued samples. Supports lowpass, highpass, and bandpass
    # filter types using the windowed sinc design method.
    #
    # @example Create and apply a lowpass filter
    #   filter = RTLSDR::DSP::Filter.lowpass(cutoff: 100_000, sample_rate: 2_048_000)
    #   filtered = filter.apply(samples)
    #
    # @example Chain multiple filters
    #   lpf = Filter.lowpass(cutoff: 100_000, sample_rate: 2_048_000)
    #   hpf = Filter.highpass(cutoff: 1000, sample_rate: 2_048_000)
    #   filtered = hpf.apply(lpf.apply(samples))
    class Filter
      # @return [Array<Float>] Filter coefficients
      attr_reader :coefficients

      # @return [Integer] Number of filter taps
      attr_reader :taps

      # @return [Symbol] Filter type (:lowpass, :highpass, :bandpass)
      attr_reader :filter_type

      # @return [Symbol] Window function used (:hamming, :hanning, :blackman, :kaiser)
      attr_reader :window

      # Design a lowpass FIR filter
      #
      # Creates a lowpass filter that passes frequencies below the cutoff
      # and attenuates frequencies above it.
      #
      # @param [Numeric] cutoff Cutoff frequency in Hz
      # @param [Numeric] sample_rate Sample rate in Hz
      # @param [Integer] taps Number of filter taps (more = sharper rolloff, more delay)
      # @param [Symbol] window Window function (:hamming, :hanning, :blackman)
      # @return [Filter] Configured lowpass filter
      # @example 100 kHz lowpass at 2.048 MHz sample rate
      #   filter = Filter.lowpass(cutoff: 100_000, sample_rate: 2_048_000, taps: 64)
      def self.lowpass(cutoff:, sample_rate:, taps: 63, window: :hamming)
        normalized_cutoff = cutoff.to_f / sample_rate
        coeffs = design_sinc_filter(normalized_cutoff, taps, window)
        new(coeffs, filter_type: :lowpass, window: window)
      end

      # Design a highpass FIR filter
      #
      # Creates a highpass filter that passes frequencies above the cutoff
      # and attenuates frequencies below it. Implemented via spectral inversion
      # of a lowpass filter.
      #
      # @param [Numeric] cutoff Cutoff frequency in Hz
      # @param [Numeric] sample_rate Sample rate in Hz
      # @param [Integer] taps Number of filter taps (must be odd for highpass)
      # @param [Symbol] window Window function (:hamming, :hanning, :blackman)
      # @return [Filter] Configured highpass filter
      # @example 1 kHz highpass at 48 kHz sample rate
      #   filter = Filter.highpass(cutoff: 1000, sample_rate: 48_000, taps: 63)
      def self.highpass(cutoff:, sample_rate:, taps: 63, window: :hamming)
        # Ensure odd number of taps for highpass
        taps += 1 unless taps.odd?

        normalized_cutoff = cutoff.to_f / sample_rate
        coeffs = design_sinc_filter(normalized_cutoff, taps, window)

        # Spectral inversion: negate all coefficients, add 1 to center tap
        mid = taps / 2
        coeffs = coeffs.map.with_index do |c, i|
          if i == mid
            1.0 - c
          else
            -c
          end
        end

        new(coeffs, filter_type: :highpass, window: window)
      end

      # Design a bandpass FIR filter
      #
      # Creates a bandpass filter that passes frequencies between low and high
      # cutoffs and attenuates frequencies outside that range.
      #
      # @param [Numeric] low Lower cutoff frequency in Hz
      # @param [Numeric] high Upper cutoff frequency in Hz
      # @param [Numeric] sample_rate Sample rate in Hz
      # @param [Integer] taps Number of filter taps
      # @param [Symbol] window Window function
      # @return [Filter] Configured bandpass filter
      # @example 300-3000 Hz bandpass (voice) at 48 kHz
      #   filter = Filter.bandpass(low: 300, high: 3000, sample_rate: 48_000)
      def self.bandpass(low:, high:, sample_rate:, taps: 63, window: :hamming)
        raise ArgumentError, "low must be less than high" if low >= high

        # Ensure odd number of taps
        taps += 1 unless taps.odd?

        # Design as difference of two lowpass filters
        norm_low = low.to_f / sample_rate
        norm_high = high.to_f / sample_rate

        low_coeffs = design_sinc_filter(norm_low, taps, window)
        high_coeffs = design_sinc_filter(norm_high, taps, window)

        # Bandpass = highpass(low) convolved with lowpass(high)
        # Simpler: lowpass(high) - lowpass(low) then spectral shift
        # Even simpler: subtract lowpass from highpass equivalent
        coeffs = high_coeffs.zip(low_coeffs).map { |h, l| h - l }

        new(coeffs, filter_type: :bandpass, window: window)
      end

      # Design a bandstop (notch) FIR filter
      #
      # Creates a filter that attenuates frequencies between low and high
      # cutoffs and passes frequencies outside that range.
      #
      # @param [Numeric] low Lower cutoff frequency in Hz
      # @param [Numeric] high Upper cutoff frequency in Hz
      # @param [Numeric] sample_rate Sample rate in Hz
      # @param [Integer] taps Number of filter taps
      # @param [Symbol] window Window function
      # @return [Filter] Configured bandstop filter
      def self.bandstop(low:, high:, sample_rate:, taps: 63, window: :hamming)
        raise ArgumentError, "low must be less than high" if low >= high

        taps += 1 unless taps.odd?

        norm_low = low.to_f / sample_rate
        norm_high = high.to_f / sample_rate

        low_coeffs = design_sinc_filter(norm_low, taps, window)
        high_coeffs = design_sinc_filter(norm_high, taps, window)

        # Bandstop = allpass - bandpass = lowpass(low) + highpass(high)
        # highpass = spectral inversion of lowpass
        mid = taps / 2

        # Create highpass from high cutoff
        hp_coeffs = high_coeffs.map.with_index do |c, i|
          i == mid ? 1.0 - c : -c
        end

        # Add lowpass(low) + highpass(high)
        coeffs = low_coeffs.zip(hp_coeffs).map { |l, h| l + h }

        new(coeffs, filter_type: :bandstop, window: window)
      end

      # Create a filter from existing coefficients
      #
      # @param [Array<Float>] coefficients Filter coefficients
      # @param [Symbol] filter_type Type of filter
      # @param [Symbol] window Window function used
      def initialize(coefficients, filter_type: :custom, window: :hamming)
        @coefficients = coefficients.freeze
        @taps = coefficients.length
        @filter_type = filter_type
        @window = window
      end

      # Apply the filter to samples using convolution
      #
      # @param [Array<Complex, Float>] samples Input samples
      # @return [Array<Complex, Float>] Filtered samples
      # @example Filter complex IQ samples
      #   filtered = filter.apply(iq_samples)
      def apply(samples)
        return [] if samples.empty?

        convolve(samples, @coefficients)
      end

      # Apply filter with zero-phase (forward-backward filtering)
      #
      # Filters the signal twice (forward then backward) to eliminate
      # phase distortion. The effective filter order is doubled.
      #
      # @param [Array<Complex, Float>] samples Input samples
      # @return [Array<Complex, Float>] Zero-phase filtered samples
      def apply_zero_phase(samples)
        return [] if samples.empty?

        # Forward filter
        forward = convolve(samples, @coefficients)
        # Reverse
        reversed = forward.reverse
        # Backward filter
        backward = convolve(reversed, @coefficients)
        # Reverse again
        backward.reverse
      end

      # Get the frequency response of the filter
      #
      # Computes the magnitude response at the specified number of frequency points.
      # Requires FFTW3 to be available.
      #
      # @param [Integer] points Number of frequency points
      # @return [Array<Float>] Magnitude response (linear scale)
      # @raise [RuntimeError] if FFTW3 is not available
      def frequency_response(points = 512)
        raise "FFTW3 required for frequency response" unless DSP.fft_available?

        # Zero-pad coefficients to desired length
        padded = @coefficients + Array.new(points - @taps, 0.0)
        # Convert to complex
        complex_padded = padded.map { |c| Complex(c, 0) }
        # FFT
        spectrum = DSP.fft(complex_padded)
        # Return magnitude
        spectrum.map(&:abs)
      end

      # Get the group delay of the filter
      #
      # For a symmetric FIR filter, the group delay is constant and equal
      # to (taps - 1) / 2 samples.
      #
      # @return [Float] Group delay in samples
      def group_delay
        (@taps - 1) / 2.0
      end

      # @return [String] Human-readable filter description
      def to_s
        "#{@filter_type.capitalize} FIR filter (#{@taps} taps, #{@window} window)"
      end

      # Design windowed sinc filter coefficients
      #
      # @param [Float] cutoff Normalized cutoff frequency (0 to 0.5)
      # @param [Integer] taps Number of taps
      # @param [Symbol] window Window function
      # @return [Array<Float>] Filter coefficients
      def self.design_sinc_filter(cutoff, taps, window)
        # Ensure odd number of taps for symmetric filter
        taps += 1 unless taps.odd?
        mid = (taps - 1) / 2.0

        coeffs = Array.new(taps) do |n|
          m = n - mid

          # Sinc function (impulse response of ideal lowpass)
          sinc = if m.abs < 1e-10
                   2 * cutoff
                 else
                   Math.sin(2 * Math::PI * cutoff * m) / (Math::PI * m)
                 end

          # Apply window
          w = window_function(n, taps, window)
          sinc * w
        end

        # Normalize for unity gain at DC
        sum = coeffs.sum
        coeffs.map { |c| c / sum }
      end

      # Calculate window function value
      #
      # @param [Integer] index Sample index
      # @param [Integer] length Window length
      # @param [Symbol] type Window type (:hamming, :hanning, :blackman, :rectangular, :none)
      # @return [Float] Window value
      def self.window_function(index, length, type)
        # Default to Hamming for unknown types
        type = :hamming unless %i[hamming hanning blackman rectangular none].include?(type)

        case type
        when :hamming
          0.54 - (0.46 * Math.cos(2 * Math::PI * index / (length - 1)))
        when :hanning
          0.5 * (1 - Math.cos(2 * Math::PI * index / (length - 1)))
        when :blackman
          0.42 - (0.5 * Math.cos(2 * Math::PI * index / (length - 1))) +
            (0.08 * Math.cos(4 * Math::PI * index / (length - 1)))
        else # :rectangular, :none
          1.0
        end
      end

      private_class_method :design_sinc_filter, :window_function

      private

      # Convolve samples with filter coefficients
      def convolve(samples, filter)
        n = samples.length
        m = filter.length
        result = Array.new(n)

        n.times do |i|
          sum = samples[0].is_a?(Complex) ? Complex(0, 0) : 0.0
          m.times do |j|
            k = i - j + (m / 2)
            sum += samples[k] * filter[j] if k >= 0 && k < n
          end
          result[i] = sum
        end

        result
      end
    end
  end
end
