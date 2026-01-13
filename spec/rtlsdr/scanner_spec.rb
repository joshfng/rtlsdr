# frozen_string_literal: true

require "spec_helper"

RSpec.describe RTLSDR::Scanner do
  let(:mock_device) { instance_double(RTLSDR::Device) }
  let(:start_freq) { 100_000_000 }
  let(:end_freq) { 102_000_000 }
  let(:step_size) { 1_000_000 }
  let(:dwell_time) { 0.01 }

  let(:scanner) do
    described_class.new(
      mock_device,
      start_freq: start_freq,
      end_freq: end_freq,
      step_size: step_size,
      dwell_time: dwell_time
    )
  end

  # Helper to generate test IQ samples
  def generate_test_samples(count, power_level = 0.5)
    Array.new(count) { Complex(power_level, power_level) }
  end

  describe "#initialize" do
    it "sets device" do
      expect(scanner.device).to eq(mock_device)
    end

    it "sets frequency range" do
      expect(scanner.start_freq).to eq(start_freq)
      expect(scanner.end_freq).to eq(end_freq)
    end

    it "sets scan parameters" do
      expect(scanner.step_size).to eq(step_size)
      expect(scanner.dwell_time).to eq(dwell_time)
    end

    it "starts with scanning flag false" do
      expect(scanner.scanning?).to be false
    end

    it "uses default step size when not provided" do
      scanner = described_class.new(mock_device, start_freq: 100e6, end_freq: 200e6)
      expect(scanner.step_size).to eq(1_000_000)
    end

    it "uses default dwell time when not provided" do
      scanner = described_class.new(mock_device, start_freq: 100e6, end_freq: 200e6)
      expect(scanner.dwell_time).to eq(0.1)
    end
  end

  describe "#frequencies" do
    it "returns array of frequencies" do
      freqs = scanner.frequencies
      expect(freqs).to be_an(Array)
      expect(freqs).to all(be_a(Integer))
    end

    it "includes start and end frequencies" do
      freqs = scanner.frequencies
      expect(freqs.first).to eq(start_freq)
      expect(freqs.last).to be <= end_freq
    end

    it "steps by step_size" do
      freqs = scanner.frequencies
      expect(freqs[1] - freqs[0]).to eq(step_size)
    end

    it "calculates correct number of steps" do
      scanner = described_class.new(mock_device, start_freq: 100e6, end_freq: 105e6, step_size: 1e6)
      expect(scanner.frequencies.length).to eq(6) # 100, 101, 102, 103, 104, 105
    end
  end

  describe "#frequency_count" do
    it "returns correct count" do
      scanner = described_class.new(mock_device, start_freq: 100e6, end_freq: 105e6, step_size: 1e6)
      expect(scanner.frequency_count).to eq(6)
    end

    it "handles single frequency" do
      scanner = described_class.new(mock_device, start_freq: 100e6, end_freq: 100e6, step_size: 1e6)
      expect(scanner.frequency_count).to eq(1)
    end
  end

  describe "#scan" do
    before do
      allow(mock_device).to receive(:center_freq=)
      allow(mock_device).to receive(:read_samples).and_return(generate_test_samples(1024))
      allow(scanner).to receive(:sleep)
    end

    it "requires a block" do
      expect { scanner.scan }.to raise_error(ArgumentError, /Block required/)
    end

    it "sets scanning flag during scan" do
      scanning_during = nil
      scanner.scan do |_result|
        scanning_during = scanner.scanning?
      end
      expect(scanning_during).to be true
    end

    it "clears scanning flag after scan" do
      scanner.scan { |_result| }
      expect(scanner.scanning?).to be false
    end

    it "tunes device to each frequency" do
      scanner.frequencies.each do |freq|
        expect(mock_device).to receive(:center_freq=).with(freq)
      end
      scanner.scan { |_result| }
    end

    it "sleeps for dwell_time at each frequency" do
      freq_count = scanner.frequencies.length
      expect(scanner).to receive(:sleep).with(dwell_time).exactly(freq_count).times
      scanner.scan { |_result| }
    end

    it "reads samples at each frequency" do
      expect(mock_device).to receive(:read_samples).with(2048).exactly(scanner.frequencies.length).times
      scanner.scan(samples_per_freq: 2048) { |_result| }
    end

    it "yields result hash for each frequency" do
      results = []
      scanner.scan { |result| results << result }

      expect(results.length).to eq(scanner.frequencies.length)
      results.each do |result|
        expect(result).to include(:frequency, :power, :samples, :timestamp)
      end
    end

    it "calculates power for each frequency" do
      scanner.scan do |result|
        expect(result[:power]).to be_a(Numeric)
        expect(result[:power]).to be >= 0
      end
    end

    it "includes samples in result" do
      scanner.scan do |result|
        expect(result[:samples]).to be_an(Array)
        expect(result[:samples].first).to be_a(Complex)
      end
    end

    it "includes timestamp in result" do
      scanner.scan do |result|
        expect(result[:timestamp]).to be_a(Time)
      end
    end

    it "returns hash of all results keyed by frequency" do
      results = scanner.scan { |_result| }
      expect(results).to be_a(Hash)
      expect(results.keys).to match_array(scanner.frequencies)
    end

    it "stops early when stop is called" do
      call_count = 0
      scanner.scan do |_result|
        call_count += 1
        scanner.stop if call_count == 2
      end
      expect(call_count).to eq(2)
      expect(scanner.scanning?).to be false
    end
  end

  describe "#scan_async" do
    before do
      allow(mock_device).to receive(:center_freq=)
      allow(mock_device).to receive(:read_samples).and_return(generate_test_samples(1024))
      allow(scanner).to receive(:sleep)
    end

    it "requires a block" do
      expect { scanner.scan_async }.to raise_error(ArgumentError, /Block required/)
    end

    it "returns a Thread" do
      thread = scanner.scan_async { |_result| }
      expect(thread).to be_a(Thread)
      thread.join
    end

    it "performs scan in background thread" do
      main_thread = Thread.current
      scan_thread = nil

      thread = scanner.scan_async do |_result|
        scan_thread = Thread.current
      end
      thread.join

      expect(scan_thread).not_to eq(main_thread)
    end

    it "yields results from background thread" do
      results = []
      thread = scanner.scan_async { |result| results << result }
      thread.join

      expect(results.length).to eq(scanner.frequencies.length)
    end
  end

  describe "#find_peaks" do
    before do
      allow(mock_device).to receive(:center_freq=)
      allow(scanner).to receive(:sleep)

      # Create samples with varying power levels
      # 100 MHz: high power (0.8)
      # 101 MHz: low power (0.1)
      # 102 MHz: medium power (0.5)
      power_levels = [0.8, 0.1, 0.5]
      samples_by_freq = scanner.frequencies.each_with_index.to_h do |freq, idx|
        [freq, generate_test_samples(1024, power_levels[idx])]
      end

      allow(mock_device).to receive(:read_samples) do
        samples_by_freq[@current_freq] || generate_test_samples(1024, 0.1)
      end

      allow(mock_device).to receive(:center_freq=) do |freq|
        @current_freq = freq
      end
    end

    it "returns array of peaks" do
      peaks = scanner.find_peaks(threshold: -100)
      expect(peaks).to be_an(Array)
    end

    it "includes frequency, power, power_db, and timestamp" do
      peaks = scanner.find_peaks(threshold: -100)
      peaks.each do |peak|
        expect(peak).to include(:frequency, :power, :power_db, :timestamp)
      end
    end

    it "filters by threshold" do
      # Set threshold high enough to only catch the strongest signal
      peaks = scanner.find_peaks(threshold: -5)
      expect(peaks.length).to be < scanner.frequencies.length
    end

    it "sorts peaks by power descending" do
      peaks = scanner.find_peaks(threshold: -100)
      expect(peaks).not_to be_empty

      peak_powers = peaks.map { |p| p[:power] }
      expect(peak_powers).to eq(peak_powers.sort.reverse)
    end

    it "converts power to dB" do
      peaks = scanner.find_peaks(threshold: -100)
      peaks.each do |peak|
        expected_db = 10 * Math.log10(peak[:power] + 1e-10)
        expect(peak[:power_db]).to be_within(0.01).of(expected_db)
      end
    end

    it "returns empty array when no peaks above threshold" do
      peaks = scanner.find_peaks(threshold: 100) # Impossibly high threshold
      expect(peaks).to eq([])
    end
  end

  describe "#power_sweep" do
    before do
      allow(mock_device).to receive(:center_freq=)
      allow(mock_device).to receive(:read_samples).and_return(generate_test_samples(1024))
      allow(scanner).to receive(:sleep)
    end

    it "returns array of [frequency, power_db] pairs" do
      results = scanner.power_sweep
      expect(results).to be_an(Array)
      expect(results.first).to be_an(Array)
      expect(results.first.length).to eq(2)
    end

    it "includes all frequencies" do
      results = scanner.power_sweep
      freqs = results.map(&:first)
      expect(freqs).to match_array(scanner.frequencies)
    end

    it "includes power in dB" do
      results = scanner.power_sweep
      results.each do |_freq, power_db|
        expect(power_db).to be_a(Numeric)
      end
    end

    it "calculates power correctly" do
      allow(RTLSDR::DSP).to receive(:average_power).and_return(0.5)
      results = scanner.power_sweep

      expected_db = 10 * Math.log10(0.5 + 1e-10)
      results.each do |_freq, power_db|
        expect(power_db).to be_within(0.01).of(expected_db)
      end
    end
  end

  describe "#stop" do
    it "sets scanning flag to false" do
      scanner.instance_variable_set(:@scanning, true)
      scanner.stop
      expect(scanner.scanning?).to be false
    end

    it "returns false" do
      expect(scanner.stop).to be false
    end
  end

  describe "#scanning?" do
    it "returns current scanning state" do
      expect(scanner.scanning?).to be false

      scanner.instance_variable_set(:@scanning, true)
      expect(scanner.scanning?).to be true

      scanner.instance_variable_set(:@scanning, false)
      expect(scanner.scanning?).to be false
    end
  end

  describe "#configure" do
    it "updates start_freq" do
      scanner.configure(start_freq: 200e6)
      expect(scanner.start_freq).to eq(200e6)
    end

    it "updates end_freq" do
      scanner.configure(end_freq: 300e6)
      expect(scanner.end_freq).to eq(300e6)
    end

    it "updates step_size" do
      scanner.configure(step_size: 500_000)
      expect(scanner.step_size).to eq(500_000)
    end

    it "updates dwell_time" do
      scanner.configure(dwell_time: 0.05)
      expect(scanner.dwell_time).to eq(0.05)
    end

    it "only updates non-nil parameters" do
      original_start = scanner.start_freq
      scanner.configure(end_freq: 300e6)
      expect(scanner.start_freq).to eq(original_start)
      expect(scanner.end_freq).to eq(300e6)
    end

    it "returns self for chaining" do
      result = scanner.configure(step_size: 500_000)
      expect(result).to eq(scanner)
    end

    it "allows chaining multiple configure calls" do
      scanner.configure(start_freq: 200e6).configure(end_freq: 300e6)
      expect(scanner.start_freq).to eq(200e6)
      expect(scanner.end_freq).to eq(300e6)
    end
  end

  describe "#inspect" do
    it "returns string representation" do
      str = scanner.inspect
      expect(str).to be_a(String)
      expect(str).to include("RTLSDR::Scanner")
    end

    it "includes frequency range in MHz" do
      str = scanner.inspect
      expect(str).to include("#{start_freq / 1e6}MHz")
      expect(str).to include("#{end_freq / 1e6}MHz")
    end

    it "includes step size and dwell time" do
      str = scanner.inspect
      expect(str).to include("step=")
      expect(str).to include("dwell=")
    end
  end
end
