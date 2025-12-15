# frozen_string_literal: true

require "spec_helper"

RSpec.describe RTLSDR::DSP do
  describe ".fft_available?" do
    it "returns a boolean" do
      expect(described_class.fft_available?).to be(true).or be(false)
    end
  end

  describe ".apply_window" do
    let(:samples) { Array.new(8) { Complex(1, 0) } }

    it "applies hanning window by default" do
      windowed = described_class.apply_window(samples)
      expect(windowed.length).to eq(samples.length)
      # First and last values should be near zero (windowed down)
      expect(windowed[0].abs).to be < 0.01
      expect(windowed[-1].abs).to be < 0.01
      # Middle values should be near 1
      expect(windowed[4].abs).to be > 0.9
    end

    it "applies hamming window" do
      windowed = described_class.apply_window(samples, :hamming)
      expect(windowed.length).to eq(samples.length)
      # Hamming window has non-zero endpoints
      expect(windowed[0].abs).to be_within(0.1).of(0.08)
    end

    it "applies blackman window" do
      windowed = described_class.apply_window(samples, :blackman)
      expect(windowed.length).to eq(samples.length)
      # Blackman window has near-zero endpoints
      expect(windowed[0].abs).to be < 0.01
    end

    it "returns unchanged with :none window" do
      windowed = described_class.apply_window(samples, :none)
      expect(windowed).to eq(samples)
    end

    it "handles empty array" do
      expect(described_class.apply_window([])).to eq([])
    end
  end

  describe ".fft_shift" do
    it "shifts spectrum to center DC" do
      spectrum = [1, 2, 3, 4, 5, 6, 7, 8]
      shifted = described_class.fft_shift(spectrum)
      # Elements after midpoint come first, then before
      expect(shifted).to eq([5, 6, 7, 8, 1, 2, 3, 4])
    end

    it "handles odd-length spectrum" do
      spectrum = [1, 2, 3, 4, 5]
      shifted = described_class.fft_shift(spectrum)
      expect(shifted).to eq([3, 4, 5, 1, 2])
    end
  end

  describe ".ifft_shift" do
    it "reverses fft_shift" do
      spectrum = [1, 2, 3, 4, 5, 6, 7, 8]
      shifted = described_class.fft_shift(spectrum)
      unshifted = described_class.ifft_shift(shifted)
      expect(unshifted).to eq(spectrum)
    end
  end

  # FFT-dependent tests
  context "when FFTW3 is available", if: RTLSDR::DSP.fft_available? do
    describe ".fft" do
      it "computes forward FFT" do
        samples = Array.new(8) { Complex(1, 0) }
        spectrum = described_class.fft(samples)
        expect(spectrum.length).to eq(8)
        expect(spectrum).to all(be_a(Complex))
      end
    end

    describe ".ifft" do
      it "computes inverse FFT" do
        samples = [Complex(1, 2), Complex(3, 4), Complex(5, 6), Complex(7, 8)]
        spectrum = described_class.fft(samples)
        reconstructed = described_class.ifft(spectrum)

        samples.each_with_index do |sample, i|
          expect(reconstructed[i].real).to be_within(0.0001).of(sample.real)
          expect(reconstructed[i].imag).to be_within(0.0001).of(sample.imag)
        end
      end
    end

    describe ".fft_power_db" do
      it "returns power spectrum in dB" do
        # DC signal
        samples = Array.new(8) { Complex(1, 0) }
        power_db = described_class.fft_power_db(samples, window: :none)

        expect(power_db.length).to eq(8)
        expect(power_db).to all(be_a(Float))
        # DC bin should be highest
        expect(power_db[0]).to be > power_db[1]
      end
    end
  end

  context "when FFTW3 is not available", unless: RTLSDR::DSP.fft_available? do
    describe ".fft" do
      it "raises error" do
        expect { described_class.fft([Complex(1, 0)]) }.to raise_error(RuntimeError, /FFTW3/)
      end
    end

    describe ".ifft" do
      it "raises error" do
        expect { described_class.ifft([Complex(1, 0)]) }.to raise_error(RuntimeError, /FFTW3/)
      end
    end
  end

  describe "decimation and resampling" do
    let(:samples) do
      # Generate a simple test signal
      Array.new(100) { |i| Complex(Math.sin(2 * Math::PI * i / 10), 0) }
    end

    describe ".decimate" do
      it "reduces sample count by factor" do
        decimated = described_class.decimate(samples, 4)
        # Should be roughly 1/4 the original length
        expect(decimated.length).to eq(25)
      end

      it "returns original when factor is 1" do
        result = described_class.decimate(samples, 1)
        expect(result).to eq(samples)
      end

      it "returns original when factor is less than 1" do
        result = described_class.decimate(samples, 0)
        expect(result).to eq(samples)
      end

      it "returns complex values" do
        decimated = described_class.decimate(samples, 2)
        expect(decimated).to all(be_a(Complex))
      end
    end

    describe ".interpolate" do
      it "increases sample count by factor" do
        short_samples = samples.take(10)
        interpolated = described_class.interpolate(short_samples, 4)
        expect(interpolated.length).to eq(40)
      end

      it "returns original when factor is 1" do
        short_samples = samples.take(10)
        result = described_class.interpolate(short_samples, 1)
        expect(result).to eq(short_samples)
      end

      it "returns complex values" do
        short_samples = samples.take(10)
        interpolated = described_class.interpolate(short_samples, 2)
        expect(interpolated).to all(be_a(Complex))
      end
    end

    describe ".resample" do
      it "resamples to higher rate" do
        short_samples = samples.take(10)
        resampled = described_class.resample(short_samples, from_rate: 1000, to_rate: 2000)
        expect(resampled.length).to eq(20)
      end

      it "resamples to lower rate" do
        short_samples = samples.take(100)
        resampled = described_class.resample(short_samples, from_rate: 2000, to_rate: 1000)
        expect(resampled.length).to eq(50)
      end

      it "returns original when rates are equal" do
        short_samples = samples.take(10)
        result = described_class.resample(short_samples, from_rate: 1000, to_rate: 1000)
        expect(result).to eq(short_samples)
      end

      it "handles non-integer ratios" do
        short_samples = samples.take(48)
        resampled = described_class.resample(short_samples, from_rate: 48_000, to_rate: 44_100)
        # Expected: 48 * 44100/48000 = 44.1, so ~44 samples
        expect(resampled.length).to be_within(2).of(44)
      end
    end
  end
end
