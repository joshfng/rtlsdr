# frozen_string_literal: true

module RTLSDR
  # Demodulation algorithms for common radio signals
  #
  # The Demod module provides methods for demodulating FM, AM, and SSB signals
  # from complex IQ samples. All demodulators output real-valued audio samples
  # that can be played back or written to audio files.
  #
  # @example Demodulate FM radio
  #   samples = device.read_samples(262144)
  #   audio = RTLSDR::Demod.fm(samples, sample_rate: 2_048_000)
  #
  # @example Demodulate AM signal
  #   audio = RTLSDR::Demod.am(samples, sample_rate: 2_048_000)
  #
  # @example Demodulate SSB (upper sideband)
  #   audio = RTLSDR::Demod.usb(samples, sample_rate: 2_048_000, bfo_offset: 1500)
  module Demod
    # =========================================================================
    # Helper Functions
    # =========================================================================

    # Generate a complex oscillator (carrier signal)
    #
    # Creates an array of complex exponentials: exp(j * 2 * pi * freq * t)
    # Used for frequency shifting (mixing) signals.
    #
    # @param [Integer] length Number of samples to generate
    # @param [Numeric] frequency Oscillator frequency in Hz
    # @param [Numeric] sample_rate Sample rate in Hz
    # @return [Array<Complex>] Complex oscillator samples
    # @example Generate 1 kHz oscillator at 48 kHz sample rate
    #   osc = RTLSDR::Demod.complex_oscillator(1024, 1000, 48_000)
    def self.complex_oscillator(length, frequency, sample_rate)
      omega = 2.0 * Math::PI * frequency / sample_rate
      Array.new(length) { |i| Complex(Math.cos(omega * i), Math.sin(omega * i)) }
    end

    # Mix (frequency shift) a signal
    #
    # Multiplies the input signal by a complex oscillator to shift its
    # frequency. Positive frequency shifts up, negative shifts down.
    #
    # @param [Array<Complex>] samples Input complex samples
    # @param [Numeric] frequency Shift frequency in Hz (negative = shift down)
    # @param [Numeric] sample_rate Sample rate in Hz
    # @return [Array<Complex>] Frequency-shifted samples
    # @example Shift signal down by 10 kHz
    #   shifted = RTLSDR::Demod.mix(samples, -10_000, 2_048_000)
    def self.mix(samples, frequency, sample_rate)
      omega = 2.0 * Math::PI * frequency / sample_rate
      samples.each_with_index.map do |sample, i|
        sample * Complex(Math.cos(omega * i), Math.sin(omega * i))
      end
    end

    # Compute instantaneous phase difference (FM discriminator core)
    #
    # Calculates the phase difference between consecutive samples using
    # the polar discriminator method. This is the core of FM demodulation.
    #
    # @param [Array<Complex>] samples Input complex samples
    # @return [Array<Float>] Phase differences in radians (-π to π)
    # @example Get FM baseband signal
    #   phase_diff = RTLSDR::Demod.phase_diff(samples)
    def self.phase_diff(samples)
      return [] if samples.length < 2

      result = Array.new(samples.length - 1)
      (1...samples.length).each do |i|
        prev = samples[i - 1]
        curr = samples[i]
        # Polar discriminator: arg(curr * conj(prev))
        # = atan2(curr.imag*prev.real - curr.real*prev.imag,
        #         curr.real*prev.real + curr.imag*prev.imag)
        result[i - 1] = Math.atan2(
          (curr.imag * prev.real) - (curr.real * prev.imag),
          (curr.real * prev.real) + (curr.imag * prev.imag)
        )
      end
      result
    end

    # Apply de-emphasis filter for FM audio
    #
    # FM broadcast uses pre-emphasis to boost high frequencies before
    # transmission. This filter reverses that effect. Standard time
    # constants are 75µs (US/Korea) or 50µs (Europe/Australia).
    #
    # @param [Array<Float>] samples Input audio samples
    # @param [Float] tau Time constant in seconds (75e-6 for US, 50e-6 for EU)
    # @param [Numeric] sample_rate Sample rate in Hz
    # @return [Array<Float>] De-emphasized audio samples
    def self.deemphasis(samples, tau, sample_rate)
      return samples if samples.empty? || tau <= 0

      # First-order IIR lowpass: y[n] = (1-alpha)*x[n] + alpha*y[n-1]
      alpha = Math.exp(-1.0 / (tau * sample_rate))
      one_minus_alpha = 1.0 - alpha

      result = Array.new(samples.length)
      result[0] = samples[0] * one_minus_alpha

      (1...samples.length).each do |i|
        result[i] = (samples[i] * one_minus_alpha) + (result[i - 1] * alpha)
      end

      result
    end

    # =========================================================================
    # FM Demodulation
    # =========================================================================

    # Wideband FM demodulation (broadcast radio)
    #
    # Demodulates wideband FM signals such as broadcast FM radio (88-108 MHz).
    # Applies a polar discriminator followed by de-emphasis filtering and
    # decimation to the audio sample rate.
    #
    # @param [Array<Complex>] samples Input IQ samples
    # @param [Integer] sample_rate Input sample rate in Hz
    # @param [Integer] audio_rate Output audio sample rate (default: 48000)
    # @param [Integer] deviation FM deviation in Hz (default: 75000 for WBFM)
    # @param [Float, nil] tau De-emphasis time constant (75e-6 US, 50e-6 EU, nil to disable)
    # @return [Array<Float>] Demodulated audio samples (normalized to -1.0 to 1.0)
    # @example Demodulate FM broadcast
    #   audio = RTLSDR::Demod.fm(samples, sample_rate: 2_048_000)
    # @example European de-emphasis
    #   audio = RTLSDR::Demod.fm(samples, sample_rate: 2_048_000, tau: 50e-6)
    def self.fm(samples, sample_rate:, audio_rate: 48_000, deviation: 75_000, tau: 7.5e-5)
      return [] if samples.empty?

      # Step 1: FM discriminator (phase difference)
      demodulated = phase_diff(samples)

      # Step 2: Scale by deviation to get normalized audio
      # The discriminator output is in radians per sample
      # Scale factor: sample_rate / (2 * pi * deviation)
      scale = sample_rate.to_f / (2.0 * Math::PI * deviation)
      demodulated = demodulated.map { |s| s * scale }

      # Step 3: Apply de-emphasis filter (if tau specified)
      demodulated = deemphasis(demodulated, tau, sample_rate) if tau&.positive?

      # Step 4: Decimate to audio rate
      if sample_rate != audio_rate
        # Convert to complex for DSP.resample, then back to real
        complex_samples = demodulated.map { |s| Complex(s, 0) }
        resampled = DSP.resample(complex_samples, from_rate: sample_rate, to_rate: audio_rate)
        demodulated = resampled.map(&:real)
      end

      # Normalize output
      normalize_audio(demodulated)
    end

    # Narrowband FM demodulation (voice radio)
    #
    # Demodulates narrowband FM signals such as amateur radio, FRS/GMRS,
    # and public safety communications. Uses smaller deviation than WBFM.
    #
    # @param [Array<Complex>] samples Input IQ samples
    # @param [Integer] sample_rate Input sample rate in Hz
    # @param [Integer] audio_rate Output audio sample rate (default: 48000)
    # @param [Integer] deviation FM deviation in Hz (default: 5000 for NBFM)
    # @return [Array<Float>] Demodulated audio samples
    # @example Demodulate NBFM voice
    #   audio = RTLSDR::Demod.nfm(samples, sample_rate: 2_048_000)
    def self.nfm(samples, sample_rate:, audio_rate: 48_000, deviation: 5_000)
      # NBFM doesn't use de-emphasis
      fm(samples, sample_rate: sample_rate, audio_rate: audio_rate, deviation: deviation, tau: nil)
    end

    # =========================================================================
    # AM Demodulation
    # =========================================================================

    # AM demodulation using envelope detection
    #
    # Demodulates AM signals by extracting the magnitude (envelope) of the
    # complex signal. This is the simplest AM demodulation method.
    #
    # @param [Array<Complex>] samples Input IQ samples
    # @param [Integer] sample_rate Input sample rate in Hz
    # @param [Integer] audio_rate Output audio sample rate (default: 48000)
    # @param [Integer] audio_bandwidth Audio lowpass filter cutoff (default: 5000)
    # @return [Array<Float>] Demodulated audio samples
    # @example Demodulate AM broadcast
    #   audio = RTLSDR::Demod.am(samples, sample_rate: 2_048_000)
    def self.am(samples, sample_rate:, audio_rate: 48_000, audio_bandwidth: 5_000)
      return [] if samples.empty?

      # Step 1: Envelope detection (magnitude)
      envelope = DSP.magnitude(samples)

      # Step 2: Remove DC (carrier component)
      # Use a simple high-pass by subtracting mean
      mean = envelope.sum / envelope.length.to_f
      audio = envelope.map { |s| s - mean }

      # Step 3: Lowpass filter to audio bandwidth
      if audio_bandwidth < sample_rate / 2
        filter = DSP::Filter.lowpass(
          cutoff: audio_bandwidth,
          sample_rate: sample_rate,
          taps: 63
        )
        complex_audio = audio.map { |s| Complex(s, 0) }
        audio = filter.apply(complex_audio).map(&:real)
      end

      # Step 4: Decimate to audio rate
      if sample_rate != audio_rate
        complex_audio = audio.map { |s| Complex(s, 0) }
        resampled = DSP.resample(complex_audio, from_rate: sample_rate, to_rate: audio_rate)
        audio = resampled.map(&:real)
      end

      normalize_audio(audio)
    end

    # AM demodulation with synchronous detection
    #
    # Demodulates AM using synchronous detection, which provides better
    # performance than envelope detection, especially for weak signals
    # or signals with selective fading.
    #
    # @param [Array<Complex>] samples Input IQ samples
    # @param [Integer] sample_rate Input sample rate in Hz
    # @param [Integer] audio_rate Output audio sample rate (default: 48000)
    # @param [Integer] audio_bandwidth Audio lowpass filter cutoff (default: 5000)
    # @return [Array<Float>] Demodulated audio samples
    def self.am_sync(samples, sample_rate:, audio_rate: 48_000, audio_bandwidth: 5_000)
      return [] if samples.empty?

      # Synchronous AM detection:
      # 1. Estimate carrier phase using simple PLL-like approach
      # 2. Multiply by recovered carrier to get baseband
      # 3. Take real part

      # Simple carrier recovery: use average phase
      # For better performance, a proper PLL would be needed
      phases = DSP.phase(samples)
      avg_phase = phases.sum / phases.length.to_f

      # Mix to baseband using recovered carrier phase
      audio = samples.map do |sample|
        # Multiply by exp(-j*avg_phase) and take real part
        rotated = sample * Complex(Math.cos(-avg_phase), Math.sin(-avg_phase))
        rotated.real
      end

      # Remove DC
      mean = audio.sum / audio.length.to_f
      audio = audio.map { |s| s - mean }

      # Lowpass filter
      if audio_bandwidth < sample_rate / 2
        filter = DSP::Filter.lowpass(
          cutoff: audio_bandwidth,
          sample_rate: sample_rate,
          taps: 63
        )
        complex_audio = audio.map { |s| Complex(s, 0) }
        audio = filter.apply(complex_audio).map(&:real)
      end

      # Decimate to audio rate
      if sample_rate != audio_rate
        complex_audio = audio.map { |s| Complex(s, 0) }
        resampled = DSP.resample(complex_audio, from_rate: sample_rate, to_rate: audio_rate)
        audio = resampled.map(&:real)
      end

      normalize_audio(audio)
    end

    # =========================================================================
    # SSB Demodulation
    # =========================================================================

    # Upper Sideband (USB) demodulation
    #
    # Demodulates USB signals commonly used in amateur radio above 10 MHz.
    # Uses a Beat Frequency Oscillator (BFO) to convert the sideband to audio.
    #
    # @param [Array<Complex>] samples Input IQ samples
    # @param [Integer] sample_rate Input sample rate in Hz
    # @param [Integer] audio_rate Output audio sample rate (default: 48000)
    # @param [Integer] bfo_offset BFO offset frequency in Hz (default: 1500)
    # @param [Integer] audio_bandwidth Audio lowpass filter cutoff (default: 3000)
    # @return [Array<Float>] Demodulated audio samples
    # @example Demodulate USB signal
    #   audio = RTLSDR::Demod.usb(samples, sample_rate: 2_048_000, bfo_offset: 1500)
    def self.usb(samples, sample_rate:, audio_rate: 48_000, bfo_offset: 1500, audio_bandwidth: 3_000)
      return [] if samples.empty?

      # USB: Mix down by BFO offset, take real part
      # The upper sideband appears above the carrier, so we shift down
      mixed = mix(samples, -bfo_offset, sample_rate)

      # Lowpass filter to audio bandwidth
      filter = DSP::Filter.lowpass(
        cutoff: audio_bandwidth,
        sample_rate: sample_rate,
        taps: 127
      )
      filtered = filter.apply(mixed)

      # Take real part for audio
      audio = filtered.map(&:real)

      # Decimate to audio rate
      if sample_rate != audio_rate
        complex_audio = audio.map { |s| Complex(s, 0) }
        resampled = DSP.resample(complex_audio, from_rate: sample_rate, to_rate: audio_rate)
        audio = resampled.map(&:real)
      end

      normalize_audio(audio)
    end

    # Lower Sideband (LSB) demodulation
    #
    # Demodulates LSB signals commonly used in amateur radio below 10 MHz.
    # Uses a Beat Frequency Oscillator (BFO) to convert the sideband to audio.
    #
    # @param [Array<Complex>] samples Input IQ samples
    # @param [Integer] sample_rate Input sample rate in Hz
    # @param [Integer] audio_rate Output audio sample rate (default: 48000)
    # @param [Integer] bfo_offset BFO offset frequency in Hz (default: 1500)
    # @param [Integer] audio_bandwidth Audio lowpass filter cutoff (default: 3000)
    # @return [Array<Float>] Demodulated audio samples
    # @example Demodulate LSB signal
    #   audio = RTLSDR::Demod.lsb(samples, sample_rate: 2_048_000, bfo_offset: 1500)
    def self.lsb(samples, sample_rate:, audio_rate: 48_000, bfo_offset: 1500, audio_bandwidth: 3_000)
      return [] if samples.empty?

      # LSB: Mix up by BFO offset, take real part
      # The lower sideband appears below the carrier, so we shift up
      mixed = mix(samples, bfo_offset, sample_rate)

      # Lowpass filter to audio bandwidth
      filter = DSP::Filter.lowpass(
        cutoff: audio_bandwidth,
        sample_rate: sample_rate,
        taps: 127
      )
      filtered = filter.apply(mixed)

      # Take real part for audio
      audio = filtered.map(&:real)

      # Decimate to audio rate
      if sample_rate != audio_rate
        complex_audio = audio.map { |s| Complex(s, 0) }
        resampled = DSP.resample(complex_audio, from_rate: sample_rate, to_rate: audio_rate)
        audio = resampled.map(&:real)
      end

      normalize_audio(audio)
    end

    # =========================================================================
    # FSK Demodulation
    # =========================================================================

    # FSK (Frequency Shift Keying) demodulation
    #
    # Demodulates FSK signals by using an FM discriminator to extract
    # instantaneous frequency, then thresholding to recover bits.
    # FSK encodes data by switching between two frequencies (mark and space).
    #
    # @param [Array<Complex>] samples Input IQ samples
    # @param [Integer] sample_rate Input sample rate in Hz
    # @param [Numeric] baud_rate Symbol rate in baud (symbols per second)
    # @param [Boolean] invert Swap mark/space interpretation (default: false)
    # @return [Array<Integer>] Recovered bits (0 or 1)
    # @example Demodulate 1200 baud FSK
    #   bits = RTLSDR::Demod.fsk(samples, sample_rate: 48_000, baud_rate: 1200)
    # @example Demodulate RTTY at 45.45 baud
    #   bits = RTLSDR::Demod.fsk(samples, sample_rate: 48_000, baud_rate: 45.45)
    def self.fsk(samples, sample_rate:, baud_rate:, invert: false)
      return [] if samples.empty? || samples.length < 2

      # Step 1: FM discriminator to get instantaneous frequency
      freq = phase_diff(samples)
      return [] if freq.empty?

      # Step 2: Lowpass filter to smooth transitions (cutoff at 1.5x baud rate)
      filter_cutoff = [baud_rate * 1.5, (sample_rate / 2.0) - 1].min
      filter = DSP::Filter.lowpass(
        cutoff: filter_cutoff,
        sample_rate: sample_rate,
        taps: 63
      )
      complex_freq = freq.map { |f| Complex(f, 0) }
      smoothed = filter.apply(complex_freq).map(&:real)

      # Step 3: Decimate to ~4x baud rate for bit decisions
      target_rate = (baud_rate * 4).to_i
      target_rate = [target_rate, sample_rate].min

      if sample_rate > target_rate && target_rate.positive?
        decimated = DSP.resample(
          smoothed.map { |s| Complex(s, 0) },
          from_rate: sample_rate,
          to_rate: target_rate
        ).map(&:real)
        effective_rate = target_rate
      else
        decimated = smoothed
        effective_rate = sample_rate
      end

      return [] if decimated.empty?

      # Step 4: Threshold at midpoint to get raw bits
      threshold = decimated.sum / decimated.length.to_f
      raw_bits = decimated.map { |s| s > threshold ? 1 : 0 }
      raw_bits = raw_bits.map { |b| 1 - b } if invert

      # Step 5: Sample at symbol centers
      samples_per_symbol = effective_rate.to_f / baud_rate
      return raw_bits if samples_per_symbol < 1

      output_bits = []
      offset = (samples_per_symbol / 2.0).to_i
      index = offset

      while index < raw_bits.length
        output_bits << raw_bits[index]
        index += samples_per_symbol.round
      end

      output_bits
    end

    # FSK demodulation returning raw discriminator output
    #
    # Returns the smoothed frequency discriminator output without bit slicing.
    # Useful for visualizing FSK signals, debugging, or implementing custom
    # clock recovery algorithms.
    #
    # @param [Array<Complex>] samples Input IQ samples
    # @param [Integer] sample_rate Input sample rate in Hz
    # @param [Numeric] baud_rate Symbol rate in baud (used for filter cutoff)
    # @return [Array<Float>] Smoothed discriminator output
    # @example Get raw FSK waveform for plotting
    #   waveform = RTLSDR::Demod.fsk_raw(samples, sample_rate: 48_000, baud_rate: 1200)
    def self.fsk_raw(samples, sample_rate:, baud_rate:)
      return [] if samples.empty? || samples.length < 2

      # FM discriminator
      freq = phase_diff(samples)
      return [] if freq.empty?

      # Lowpass filter
      filter_cutoff = [baud_rate * 1.5, (sample_rate / 2.0) - 1].min
      filter = DSP::Filter.lowpass(
        cutoff: filter_cutoff,
        sample_rate: sample_rate,
        taps: 63
      )
      complex_freq = freq.map { |f| Complex(f, 0) }
      filter.apply(complex_freq).map(&:real)
    end

    # =========================================================================
    # Private Helpers
    # =========================================================================

    # Normalize audio to -1.0 to 1.0 range
    #
    # @param [Array<Float>] samples Audio samples
    # @return [Array<Float>] Normalized samples
    def self.normalize_audio(samples)
      return samples if samples.empty?

      max_val = samples.map(&:abs).max
      return samples if max_val.zero? || max_val < 1e-10

      scale = 1.0 / max_val
      samples.map { |s| s * scale * 0.9 } # Leave 10% headroom
    end

    private_class_method :normalize_audio
  end
end
