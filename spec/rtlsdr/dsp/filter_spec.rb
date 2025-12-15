# frozen_string_literal: true

require "spec_helper"

RSpec.describe RTLSDR::DSP::Filter do
  describe ".lowpass" do
    let(:filter) { described_class.lowpass(cutoff: 100_000, sample_rate: 1_000_000, taps: 31) }

    it "creates a filter with correct parameters" do
      expect(filter).to be_a(described_class)
      expect(filter.filter_type).to eq(:lowpass)
      expect(filter.taps).to eq(31)
    end

    it "has normalized coefficients" do
      sum = filter.coefficients.sum
      expect(sum).to be_within(0.001).of(1.0)
    end

    it "has symmetric coefficients" do
      coeffs = filter.coefficients
      mid = coeffs.length / 2
      coeffs.take(mid).each_with_index do |c, i|
        expect(c).to be_within(0.0001).of(coeffs[-(i + 1)])
      end
    end
  end

  describe ".highpass" do
    let(:filter) { described_class.highpass(cutoff: 100_000, sample_rate: 1_000_000, taps: 31) }

    it "creates a highpass filter" do
      expect(filter.filter_type).to eq(:highpass)
    end

    it "ensures odd number of taps" do
      filter_even = described_class.highpass(cutoff: 100_000, sample_rate: 1_000_000, taps: 30)
      expect(filter_even.taps).to be_odd
    end
  end

  describe ".bandpass" do
    let(:filter) { described_class.bandpass(low: 300, high: 3000, sample_rate: 48_000, taps: 63) }

    it "creates a bandpass filter" do
      expect(filter.filter_type).to eq(:bandpass)
    end

    it "raises error when low >= high" do
      expect do
        described_class.bandpass(low: 3000, high: 300, sample_rate: 48_000)
      end.to raise_error(ArgumentError, /low must be less than high/)
    end
  end

  describe ".bandstop" do
    let(:filter) { described_class.bandstop(low: 300, high: 3000, sample_rate: 48_000, taps: 63) }

    it "creates a bandstop filter" do
      expect(filter.filter_type).to eq(:bandstop)
    end

    it "raises error when low >= high" do
      expect do
        described_class.bandstop(low: 3000, high: 300, sample_rate: 48_000)
      end.to raise_error(ArgumentError, /low must be less than high/)
    end
  end

  describe "#apply" do
    let(:filter) { described_class.lowpass(cutoff: 100_000, sample_rate: 1_000_000, taps: 31) }
    let(:samples) { Array.new(100) { |i| Complex(Math.sin(2 * Math::PI * i / 10), 0) } }

    it "returns filtered samples" do
      filtered = filter.apply(samples)
      expect(filtered.length).to eq(samples.length)
      expect(filtered).to all(be_a(Complex))
    end

    it "handles empty input" do
      expect(filter.apply([])).to eq([])
    end

    it "works with real-valued samples" do
      real_samples = Array.new(100) { |i| Math.sin(2 * Math::PI * i / 10) }
      filtered = filter.apply(real_samples)
      expect(filtered.length).to eq(real_samples.length)
    end

    it "attenuates high frequencies" do
      # Generate low frequency signal (should pass)
      low_freq = Array.new(100) { |i| Complex(Math.sin(2 * Math::PI * i * 50_000 / 1_000_000), 0) }
      # Generate high frequency signal (should be attenuated)
      high_freq = Array.new(100) { |i| Complex(Math.sin(2 * Math::PI * i * 400_000 / 1_000_000), 0) }

      filtered_low = filter.apply(low_freq)
      filtered_high = filter.apply(high_freq)

      # Low frequency should have higher power after filtering
      power_low = filtered_low.map { |s| s.abs2 }.sum / filtered_low.length
      power_high = filtered_high.map { |s| s.abs2 }.sum / filtered_high.length

      expect(power_low).to be > power_high
    end
  end

  describe "#apply_zero_phase" do
    let(:filter) { described_class.lowpass(cutoff: 100_000, sample_rate: 1_000_000, taps: 31) }
    let(:samples) { Array.new(100) { |i| Complex(Math.sin(2 * Math::PI * i / 10), 0) } }

    it "returns filtered samples" do
      filtered = filter.apply_zero_phase(samples)
      expect(filtered.length).to eq(samples.length)
    end

    it "handles empty input" do
      expect(filter.apply_zero_phase([])).to eq([])
    end
  end

  describe "#group_delay" do
    it "returns correct group delay for linear phase filter" do
      filter = described_class.lowpass(cutoff: 100_000, sample_rate: 1_000_000, taps: 31)
      expect(filter.group_delay).to eq(15.0) # (31 - 1) / 2
    end
  end

  describe "#to_s" do
    it "returns human-readable description" do
      filter = described_class.lowpass(cutoff: 100_000, sample_rate: 1_000_000, taps: 31)
      expect(filter.to_s).to include("Lowpass")
      expect(filter.to_s).to include("31 taps")
      expect(filter.to_s).to include("hamming")
    end
  end

  describe "#frequency_response", if: RTLSDR::DSP.fft_available? do
    let(:filter) { described_class.lowpass(cutoff: 100_000, sample_rate: 1_000_000, taps: 31) }

    it "returns magnitude response" do
      response = filter.frequency_response(256)
      expect(response.length).to eq(256)
      expect(response).to all(be_a(Float))
      expect(response).to all(be >= 0)
    end

    it "shows lowpass characteristic" do
      response = filter.frequency_response(256)
      # DC should have high response
      expect(response[0]).to be > 0.5
      # Nyquist should have low response
      expect(response[128]).to be < 0.1
    end
  end

  describe "window functions" do
    let(:sample_rate) { 1_000_000 }
    let(:cutoff) { 100_000 }

    it "supports hamming window" do
      filter = described_class.lowpass(cutoff: cutoff, sample_rate: sample_rate, window: :hamming)
      expect(filter.window).to eq(:hamming)
    end

    it "supports hanning window" do
      filter = described_class.lowpass(cutoff: cutoff, sample_rate: sample_rate, window: :hanning)
      expect(filter.window).to eq(:hanning)
    end

    it "supports blackman window" do
      filter = described_class.lowpass(cutoff: cutoff, sample_rate: sample_rate, window: :blackman)
      expect(filter.window).to eq(:blackman)
    end
  end
end
