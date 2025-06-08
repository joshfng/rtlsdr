#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/rtlsdr"

# Simple spectrum analyzer example
class SpectrumAnalyzer
  def initialize(device_index = 0)
    @device = RTLSDR.open(device_index)
    puts "Opened device: #{@device.inspect}"

    # Configure device
    @device.configure(
      frequency: 100_000_000,    # 100 MHz
      sample_rate: 2_048_000,    # 2.048 MHz
      gain: 400,                 # 40.0 dB
      agc_mode: false
    )

    puts "Device info:"
    puts "  Tuner: #{@device.tuner_name}"
    puts "  Center frequency: #{@device.center_freq / 1e6} MHz"
    puts "  Sample rate: #{@device.sample_rate / 1e6} MHz"
    puts "  Gain: #{@device.tuner_gain / 10.0} dB"
    puts "  Available gains: #{@device.tuner_gains.map { |g| g / 10.0 }} dB"
  end

  def analyze_current_frequency(samples_count = 8192)
    puts "\nAnalyzing #{samples_count} samples at #{@device.center_freq / 1e6} MHz..."

    samples = @device.read_samples(samples_count)

    avg_power = RTLSDR::DSP.average_power(samples)
    power_db = 10 * Math.log10(avg_power + 1e-10)

    magnitude = RTLSDR::DSP.magnitude(samples)
    RTLSDR::DSP.phase(samples)

    puts "  Average power: #{power_db.round(2)} dB"
    puts "  Peak magnitude: #{magnitude.max.round(4)}"
    puts "  Sample count: #{samples.length}"

    # Estimate frequency content
    freq_est = RTLSDR::DSP.estimate_frequency(samples, @device.sample_rate)
    puts "  Estimated frequency offset: #{freq_est.round(2)} Hz"

    samples
  end

  def frequency_sweep(start_freq, end_freq, step = 1_000_000)
    scanner = RTLSDR::Scanner.new(@device,
                                  start_freq: start_freq,
                                  end_freq: end_freq,
                                  step_size: step,
                                  dwell_time: 0.05)

    puts "\nPerforming frequency sweep from #{start_freq / 1e6} MHz to #{end_freq / 1e6} MHz"
    puts "Step size: #{step / 1e6} MHz"
    puts "Frequencies to scan: #{scanner.frequency_count}"

    results = scanner.power_sweep(samples_per_freq: 2048)

    puts "\nSweep results (top 10 strongest signals):"
    results.sort_by { |_freq, power| -power }.first(10).each do |freq, power_db|
      puts "  #{(freq / 1e6).round(3)} MHz: #{power_db.round(2)} dB"
    end

    results
  end

  def find_active_frequencies(start_freq, end_freq, threshold = -50)
    scanner = RTLSDR::Scanner.new(@device,
                                  start_freq: start_freq,
                                  end_freq: end_freq,
                                  step_size: 500_000)

    puts "\nScanning for active frequencies above #{threshold} dB..."
    peaks = scanner.find_peaks(threshold: threshold, samples_per_freq: 4096)

    if peaks.empty?
      puts "No signals found above #{threshold} dB threshold"
    else
      puts "Found #{peaks.length} active frequencies:"
      peaks.each do |peak|
        puts "  #{(peak[:frequency] / 1e6).round(3)} MHz: #{peak[:power_db].round(2)} dB"
      end
    end

    peaks
  end

  def monitor_frequency(frequency = 100 * 1e6, duration = 1)
    puts "\nMonitoring #{frequency / 1e6} MHz for #{duration} seconds..."

    start_time = Time.now
    sample_count = 0
    monitoring = true

    # Start async reading in a separate thread
    monitoring_thread = @device.read_samples_async(buffer_count: 8, buffer_length: 32_768) do |samples|
      next unless monitoring

      sample_count += samples.length
      elapsed = Time.now - start_time

      if elapsed >= duration
        monitoring = false
        next
      end

      avg_power = RTLSDR::DSP.average_power(samples)
      power_db = 10 * Math.log10(avg_power + 1e-10)

      print "\rTime: #{elapsed.round(1)}s, Samples: #{sample_count}, Power: #{power_db.round(2)} dB"
      $stdout.flush
    end

    # Wait for completion or timeout
    start_wait = Time.now
    sleep(0.1) while monitoring && (Time.now - start_wait) < (duration + 1.0)

    # Cancel if still running
    if @device.streaming?
      @device.cancel_async
      monitoring_thread&.join(1.0) # Wait up to 1 second for clean shutdown
    end

    puts "\nMonitoring complete. Total samples: #{sample_count}"
  end

  def close
    @device&.close
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  begin
    puts "RTL-SDR Spectrum Analyzer Example"
    puts "================================="

    # Check for devices
    puts "Available RTL-SDR devices:"
    RTLSDR.devices.each_with_index do |device, i|
      puts "  #{i}: #{device[:name]} (#{device[:usb_strings][:manufacturer]} #{device[:usb_strings][:product]})"
    end

    if RTLSDR.device_count.zero?
      puts "No RTL-SDR devices found!"
      exit 1
    end

    analyzer = SpectrumAnalyzer.new(0)

    analyzer.analyze_current_frequency(4096)

    analyzer.frequency_sweep(88_000_000, 108_000_000, 200_000)

    frequencies = analyzer.find_active_frequencies(88_000_000, 108_000_000, -60)

    frequencies.each do |freq|
      analyzer.monitor_frequency(freq[:frequency], 1)
    end

    analyzer.monitor_frequency(5)
  rescue RTLSDR::Error => e
    puts "RTL-SDR Error: #{e.message}"
    exit 1
  rescue Interrupt
    puts "\nInterrupted by user"
  ensure
    analyzer&.close
    puts "Device closed."
  end
end
