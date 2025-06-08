#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "../lib/rtlsdr"

puts "RTL-SDR Ruby Gem Basic Usage Example"
puts "====================================="

# List all available devices
puts "\nAvailable RTL-SDR devices:"
RTLSDR.devices.each_with_index do |device, i|
  puts "  #{i}: #{device[:name]}"
  puts "     Manufacturer: #{device[:usb_strings][:manufacturer]}"
  puts "     Product: #{device[:usb_strings][:product]}"
  puts "     Serial: #{device[:usb_strings][:serial]}"
end

if RTLSDR.device_count.zero?
  puts "No RTL-SDR devices found. Make sure your device is connected."
  exit 1
end

begin
  # Open the first device
  puts "\nOpening device 0..."
  device = RTLSDR.open(0)

  puts "Device opened successfully!"
  puts device.inspect

  # Get device information
  puts "\nDevice Information:"
  puts "  Name: #{device.name}"
  puts "  Tuner: #{device.tuner_name}"
  puts "  USB Info: #{device.usb_strings}"

  # Configure the device
  puts "\nConfiguring device..."
  device.configure(
    frequency: 100_000_000,    # 100 MHz
    sample_rate: 2_048_000,    # 2.048 MHz sample rate
    gain: 400                  # 40.0 dB gain (gains are in tenths of dB)
  )

  puts "Configuration complete:"
  puts "  Center frequency: #{device.center_freq / 1e6} MHz"
  puts "  Sample rate: #{device.sample_rate / 1e6} MHz"
  puts "  Current gain: #{device.tuner_gain / 10.0} dB"
  puts "  Available gains: #{device.tuner_gains.map { |g| g / 10.0 }} dB"

  # Read some samples
  puts "\nReading 1024 samples..."
  samples = device.read_samples(1024)

  puts "Read #{samples.length} complex samples"
  puts "First 5 samples:"
  samples.first(5).each_with_index do |sample, i|
    puts "  Sample #{i}: #{sample.real.round(4)} + #{sample.imag.round(4)}i (magnitude: #{sample.abs.round(4)})"
  end

  # Calculate some basic statistics
  avg_power = RTLSDR::DSP.average_power(samples)
  power_db = 10 * Math.log10(avg_power + 1e-10)
  magnitudes = RTLSDR::DSP.magnitude(samples)

  puts "\nSignal Analysis:"
  puts "  Average power: #{power_db.round(2)} dB"
  puts "  Peak magnitude: #{magnitudes.max.round(4)}"
  puts "  Min magnitude: #{magnitudes.min.round(4)}"
  puts "  RMS magnitude: #{Math.sqrt(magnitudes.map { |m| m**2 }.sum / magnitudes.length).round(4)}"

  # Demonstrate async reading for a short time
  puts "\nDemonstrating async reading for 2 seconds..."

  sample_count = 0
  start_time = Time.now

  # Start async reading
  thread = device.read_samples_async(buffer_count: 4, buffer_length: 16_384) do |samples|
    sample_count += samples.length
    elapsed = Time.now - start_time

    if elapsed >= 2.0
      device.cancel_async
      break
    end

    power = RTLSDR::DSP.average_power(samples)
    power_db = 10 * Math.log10(power + 1e-10)
    print "\rSamples received: #{sample_count}, Power: #{power_db.round(2)} dB"
    $stdout.flush
  end

  # Wait for async reading to complete
  thread.join
  puts "\nAsync reading complete. Total samples: #{sample_count}"

  # Demonstrate enumerable interface
  puts "\nDemonstrating enumerable interface (reading 3 batches)..."
  device.each(samples_per_read: 512).with_index do |samples, batch|
    power = RTLSDR::DSP.average_power(samples)
    power_db = 10 * Math.log10(power + 1e-10)
    puts "  Batch #{batch + 1}: #{samples.length} samples, power: #{power_db.round(2)} dB"

    break if batch >= 2 # Only read 3 batches
  end
rescue RTLSDR::Error => e
  puts "RTL-SDR Error: #{e.message}"
  puts "Make sure your RTL-SDR device is properly connected and not in use by another application."
  exit 1
rescue Interrupt
  puts "\nInterrupted by user"
ensure
  if device
    device.close
    puts "\nDevice closed."
  end
end

puts "\nExample completed successfully!"
