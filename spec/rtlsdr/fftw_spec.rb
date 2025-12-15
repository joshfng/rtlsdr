# frozen_string_literal: true

require "spec_helper"

RSpec.describe RTLSDR::FFTW do
  describe ".available?" do
    it "returns a boolean" do
      expect(described_class.available?).to be(true).or be(false)
    end
  end

  # Only run these tests if FFTW3 is available
  context "when FFTW3 is available", if: RTLSDR::FFTW.available? do
    describe ".forward" do
      it "returns empty array for empty input" do
        expect(described_class.forward([])).to eq([])
      end

      it "returns same number of elements as input" do
        samples = [Complex(1, 0), Complex(0, 0), Complex(0, 0), Complex(0, 0)]
        result = described_class.forward(samples)
        expect(result.length).to eq(samples.length)
      end

      it "returns complex values" do
        samples = [Complex(1, 0), Complex(0, 0), Complex(0, 0), Complex(0, 0)]
        result = described_class.forward(samples)
        expect(result).to all(be_a(Complex))
      end

      it "computes correct FFT for DC signal" do
        # All samples equal = DC only
        samples = Array.new(4) { Complex(1, 0) }
        result = described_class.forward(samples)

        # DC bin should have sum of all samples (4)
        expect(result[0].abs).to be_within(0.001).of(4.0)
        # Other bins should be near zero
        expect(result[1].abs).to be_within(0.001).of(0.0)
        expect(result[2].abs).to be_within(0.001).of(0.0)
        expect(result[3].abs).to be_within(0.001).of(0.0)
      end

      it "computes correct FFT for simple cosine" do
        # 8-point FFT of cosine at bin 1
        n = 8
        samples = Array.new(n) { |i| Complex(Math.cos(2 * Math::PI * i / n), 0) }
        result = described_class.forward(samples)

        # Should have peaks at bins 1 and N-1 (7)
        magnitudes = result.map(&:abs)
        expect(magnitudes[1]).to be_within(0.001).of(4.0)
        expect(magnitudes[7]).to be_within(0.001).of(4.0)
        # Other bins should be near zero
        expect(magnitudes[0]).to be_within(0.001).of(0.0)
        expect(magnitudes[4]).to be_within(0.001).of(0.0)
      end
    end

    describe ".backward" do
      it "returns empty array for empty input" do
        expect(described_class.backward([])).to eq([])
      end

      it "is the inverse of forward" do
        samples = [Complex(1, 2), Complex(3, 4), Complex(5, 6), Complex(7, 8)]
        spectrum = described_class.forward(samples)
        reconstructed = described_class.backward(spectrum)

        samples.each_with_index do |sample, i|
          expect(reconstructed[i].real).to be_within(0.0001).of(sample.real)
          expect(reconstructed[i].imag).to be_within(0.0001).of(sample.imag)
        end
      end
    end
  end

  context "when FFTW3 is not available", unless: RTLSDR::FFTW.available? do
    it "has a load error message" do
      expect(described_class.load_error).to be_a(String)
    end
  end
end
