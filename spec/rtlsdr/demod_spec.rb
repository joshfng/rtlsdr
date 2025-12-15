# frozen_string_literal: true

require "spec_helper"

RSpec.describe RTLSDR::Demod do
  let(:sample_rate) { 48_000 }
  let(:audio_rate) { 48_000 }

  # Helper to generate a pure tone as complex samples
  def generate_tone(frequency, sample_rate, length)
    omega = 2.0 * Math::PI * frequency / sample_rate
    Array.new(length) { |i| Complex(Math.cos(omega * i), Math.sin(omega * i)) }
  end

  # Helper to generate FM modulated signal
  def generate_fm_signal(audio_freq, deviation, sample_rate, length)
    audio_omega = 2.0 * Math::PI * audio_freq / sample_rate
    mod_index = deviation.to_f / audio_freq

    Array.new(length) do |i|
      phase = mod_index * Math.sin(audio_omega * i)
      Complex(Math.cos(phase), Math.sin(phase))
    end
  end

  # Helper to generate AM modulated signal
  def generate_am_signal(audio_freq, mod_depth, sample_rate, length)
    audio_omega = 2.0 * Math::PI * audio_freq / sample_rate

    Array.new(length) do |i|
      # AM: carrier * (1 + m * audio)
      envelope = 1.0 + (mod_depth * Math.sin(audio_omega * i))
      Complex(envelope, 0)
    end
  end

  describe ".complex_oscillator" do
    it "generates correct length" do
      osc = described_class.complex_oscillator(100, 1000, sample_rate)
      expect(osc.length).to eq(100)
    end

    it "generates complex samples" do
      osc = described_class.complex_oscillator(10, 1000, sample_rate)
      expect(osc).to all(be_a(Complex))
    end

    it "generates unit magnitude samples" do
      osc = described_class.complex_oscillator(100, 1000, sample_rate)
      magnitudes = osc.map(&:abs)
      expect(magnitudes).to all(be_within(0.0001).of(1.0))
    end

    it "starts at phase 0 (real = 1, imag = 0)" do
      osc = described_class.complex_oscillator(10, 1000, sample_rate)
      expect(osc[0].real).to be_within(0.0001).of(1.0)
      expect(osc[0].imag).to be_within(0.0001).of(0.0)
    end

    it "handles zero frequency (DC)" do
      osc = described_class.complex_oscillator(10, 0, sample_rate)
      osc.each do |sample|
        expect(sample.real).to be_within(0.0001).of(1.0)
        expect(sample.imag).to be_within(0.0001).of(0.0)
      end
    end
  end

  describe ".mix" do
    let(:samples) { generate_tone(1000, sample_rate, 100) }

    it "returns same length as input" do
      mixed = described_class.mix(samples, 500, sample_rate)
      expect(mixed.length).to eq(samples.length)
    end

    it "returns complex samples" do
      mixed = described_class.mix(samples, 500, sample_rate)
      expect(mixed).to all(be_a(Complex))
    end

    it "preserves magnitude" do
      mixed = described_class.mix(samples, 500, sample_rate)
      original_mags = samples.map(&:abs)
      mixed_mags = mixed.map(&:abs)

      original_mags.each_with_index do |mag, i|
        expect(mixed_mags[i]).to be_within(0.0001).of(mag)
      end
    end

    it "handles empty input" do
      expect(described_class.mix([], 500, sample_rate)).to eq([])
    end
  end

  describe ".phase_diff" do
    it "returns one less sample than input" do
      samples = generate_tone(1000, sample_rate, 100)
      diff = described_class.phase_diff(samples)
      expect(diff.length).to eq(99)
    end

    it "returns float values" do
      samples = generate_tone(1000, sample_rate, 100)
      diff = described_class.phase_diff(samples)
      expect(diff).to all(be_a(Float))
    end

    it "returns values in range -π to π" do
      samples = generate_tone(1000, sample_rate, 100)
      diff = described_class.phase_diff(samples)
      expect(diff).to all(be_between(-Math::PI, Math::PI))
    end

    it "detects constant phase difference for pure tone" do
      samples = generate_tone(1000, sample_rate, 100)
      diff = described_class.phase_diff(samples)

      # For a pure tone, phase diff should be constant
      expected_diff = 2.0 * Math::PI * 1000 / sample_rate
      diff.each do |d|
        expect(d).to be_within(0.001).of(expected_diff)
      end
    end

    it "handles empty input" do
      expect(described_class.phase_diff([])).to eq([])
    end

    it "handles single sample" do
      expect(described_class.phase_diff([Complex(1, 0)])).to eq([])
    end
  end

  describe ".deemphasis" do
    let(:samples) { Array.new(100) { |i| Math.sin(2.0 * Math::PI * 1000 * i / sample_rate) } }

    it "returns same length as input" do
      filtered = described_class.deemphasis(samples, 75e-6, sample_rate)
      expect(filtered.length).to eq(samples.length)
    end

    it "returns float values" do
      filtered = described_class.deemphasis(samples, 75e-6, sample_rate)
      expect(filtered).to all(be_a(Float))
    end

    it "attenuates high frequencies more than low frequencies" do
      # Generate high and low frequency signals
      low_freq = Array.new(1000) { |i| Math.sin(2.0 * Math::PI * 100 * i / sample_rate) }
      high_freq = Array.new(1000) { |i| Math.sin(2.0 * Math::PI * 10_000 * i / sample_rate) }

      low_filtered = described_class.deemphasis(low_freq, 75e-6, sample_rate)
      high_filtered = described_class.deemphasis(high_freq, 75e-6, sample_rate)

      # Compare RMS power (skip first 100 samples for filter settling)
      low_power = low_filtered[100..].map { |s| s**2 }.sum / low_filtered[100..].length
      high_power = high_filtered[100..].map { |s| s**2 }.sum / high_filtered[100..].length

      low_orig = low_freq[100..].map { |s| s**2 }.sum / low_freq[100..].length
      high_orig = high_freq[100..].map { |s| s**2 }.sum / high_freq[100..].length

      # High frequency should be attenuated more
      low_ratio = low_power / low_orig
      high_ratio = high_power / high_orig
      expect(low_ratio).to be > high_ratio
    end

    it "handles empty input" do
      expect(described_class.deemphasis([], 75e-6, sample_rate)).to eq([])
    end

    it "handles zero tau" do
      result = described_class.deemphasis(samples, 0, sample_rate)
      expect(result).to eq(samples)
    end
  end

  describe ".fm" do
    let(:fm_samples) { generate_fm_signal(1000, 5000, sample_rate, 10_000) }

    it "returns audio samples" do
      audio = described_class.fm(fm_samples, sample_rate: sample_rate, audio_rate: audio_rate, deviation: 5000)
      expect(audio).not_to be_empty
      expect(audio).to all(be_a(Float))
    end

    it "returns normalized output" do
      audio = described_class.fm(fm_samples, sample_rate: sample_rate, audio_rate: audio_rate, deviation: 5000)
      expect(audio.map(&:abs).max).to be <= 1.0
    end

    it "handles empty input" do
      expect(described_class.fm([], sample_rate: sample_rate)).to eq([])
    end

    it "demodulates FM signal correctly" do
      # Generate FM signal with known modulation
      audio_freq = 1000
      deviation = 5000
      length = 10_000

      fm_signal = generate_fm_signal(audio_freq, deviation, sample_rate, length)
      audio = described_class.fm(fm_signal, sample_rate: sample_rate, audio_rate: audio_rate, deviation: deviation, tau: nil)

      # The demodulated audio should have content (not be all zeros)
      power = audio.map { |s| s**2 }.sum / audio.length
      expect(power).to be > 0.01
    end
  end

  describe ".nfm" do
    let(:nfm_samples) { generate_fm_signal(1000, 2500, sample_rate, 10_000) }

    it "returns audio samples" do
      audio = described_class.nfm(nfm_samples, sample_rate: sample_rate, audio_rate: audio_rate)
      expect(audio).not_to be_empty
      expect(audio).to all(be_a(Float))
    end

    it "handles empty input" do
      expect(described_class.nfm([], sample_rate: sample_rate)).to eq([])
    end
  end

  describe ".am" do
    let(:am_samples) { generate_am_signal(1000, 0.5, sample_rate, 10_000) }

    it "returns audio samples" do
      audio = described_class.am(am_samples, sample_rate: sample_rate, audio_rate: audio_rate)
      expect(audio).not_to be_empty
      expect(audio).to all(be_a(Float))
    end

    it "returns normalized output" do
      audio = described_class.am(am_samples, sample_rate: sample_rate, audio_rate: audio_rate)
      expect(audio.map(&:abs).max).to be <= 1.0
    end

    it "handles empty input" do
      expect(described_class.am([], sample_rate: sample_rate)).to eq([])
    end

    it "extracts modulation from AM signal" do
      # Generate AM signal with known modulation
      audio_freq = 500
      mod_depth = 0.8
      length = 10_000

      am_signal = generate_am_signal(audio_freq, mod_depth, sample_rate, length)
      audio = described_class.am(am_signal, sample_rate: sample_rate, audio_rate: audio_rate)

      # The demodulated audio should have content
      power = audio.map { |s| s**2 }.sum / audio.length
      expect(power).to be > 0.001
    end
  end

  describe ".am_sync" do
    let(:am_samples) { generate_am_signal(1000, 0.5, sample_rate, 10_000) }

    it "returns audio samples" do
      audio = described_class.am_sync(am_samples, sample_rate: sample_rate, audio_rate: audio_rate)
      expect(audio).not_to be_empty
      expect(audio).to all(be_a(Float))
    end

    it "handles empty input" do
      expect(described_class.am_sync([], sample_rate: sample_rate)).to eq([])
    end
  end

  describe ".usb" do
    let(:ssb_samples) { generate_tone(1500, sample_rate, 10_000) }

    it "returns audio samples" do
      audio = described_class.usb(ssb_samples, sample_rate: sample_rate, audio_rate: audio_rate)
      expect(audio).not_to be_empty
      expect(audio).to all(be_a(Float))
    end

    it "returns normalized output" do
      audio = described_class.usb(ssb_samples, sample_rate: sample_rate, audio_rate: audio_rate)
      expect(audio.map(&:abs).max).to be <= 1.0
    end

    it "handles empty input" do
      expect(described_class.usb([], sample_rate: sample_rate)).to eq([])
    end
  end

  describe ".lsb" do
    let(:ssb_samples) { generate_tone(-1500, sample_rate, 10_000) }

    it "returns audio samples" do
      audio = described_class.lsb(ssb_samples, sample_rate: sample_rate, audio_rate: audio_rate)
      expect(audio).not_to be_empty
      expect(audio).to all(be_a(Float))
    end

    it "returns normalized output" do
      audio = described_class.lsb(ssb_samples, sample_rate: sample_rate, audio_rate: audio_rate)
      expect(audio.map(&:abs).max).to be <= 1.0
    end

    it "handles empty input" do
      expect(described_class.lsb([], sample_rate: sample_rate)).to eq([])
    end
  end

  describe "decimation" do
    it "decimates FM output to specified audio rate" do
      high_rate = 240_000
      audio_rate = 48_000
      fm_samples = generate_fm_signal(1000, 5000, high_rate, 100_000)

      audio = described_class.fm(fm_samples, sample_rate: high_rate, audio_rate: audio_rate, deviation: 5000, tau: nil)

      # Output should be roughly high_rate/audio_rate times smaller
      expected_length = (fm_samples.length * audio_rate / high_rate.to_f).to_i
      expect(audio.length).to be_within(expected_length * 0.1).of(expected_length)
    end
  end
end
