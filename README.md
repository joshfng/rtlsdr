# RTL-SDR Ruby Gem

A comprehensive Ruby gem for interfacing with RTL-SDR (Software Defined Radio) devices. This gem provides both low-level FFI bindings that closely match the C API and high-level Ruby-idiomatic classes for easy use.

[gem](https://rubygems.org/gems/rtlsdr) | [docs](https://rubydoc.info/gems/rtlsdr)

## Features

- **Complete C API Coverage**: All librtlsdr functions are exposed through FFI
- **Ruby Idiomatic Interface**: High-level classes with Ruby conventions
- **Async/Sync Reading**: Both synchronous and asynchronous sample reading
- **Signal Processing**: Built-in DSP functions for common operations
- **Frequency Scanning**: Sweep frequencies and find active signals
- **Enumerable Interface**: Use Ruby's enumerable methods on sample streams
- **Error Handling**: Proper Ruby exceptions for different error conditions

## Installation

First, make sure you have librtlsdr installed on your system:

### Ubuntu/Debian

```bash
sudo apt-get install librtlsdr-dev
```

### macOS (Homebrew)

```bash
brew install librtlsdr
```

### From Source

If you need to build librtlsdr from source, the gem will automatically try to build it:

```bash
git clone https://github.com/your-repo/rtlsdr-ruby.git
cd rtlsdr-ruby
bundle install
rake build_librtlsdr  # This will build librtlsdr in librtlsdr/build/install/
```

Then install the gem:

```bash
gem install rtlsdr
```

Or add to your Gemfile:

```ruby
gem 'rtlsdr'
```

## Quick Start

```ruby
require 'rtlsdr'

# List available devices
puts "Found #{RTLSDR.device_count} RTL-SDR devices:"
RTLSDR.devices.each_with_index do |device, i|
  puts "#{i}: #{device[:name]} (#{device[:usb_strings][:product]})"
end

# Open first device
device = RTLSDR.open(0)

# Configure for FM radio
device.configure(
  frequency: 100_500_000,    # 100.5 MHz
  sample_rate: 2_048_000,    # 2.048 MHz
  gain: 400                  # 40.0 dB
)

# Read some samples
samples = device.read_samples(1024)
puts "Read #{samples.length} complex samples"

# Calculate average power
power = RTLSDR::DSP.average_power(samples)
power_db = 10 * Math.log10(power + 1e-10)
puts "Signal power: #{power_db.round(2)} dB"

device.close
```

## Device Control

### Opening and Configuring Devices

```ruby
# Open specific device by index
device = RTLSDR.open(0)

# Get device information
puts device.name          # Device name
puts device.tuner_name    # Tuner chip name
puts device.usb_strings   # USB manufacturer, product, serial

# Configure all at once
device.configure(
  frequency: 433_920_000,     # 433.92 MHz
  sample_rate: 2_048_000,     # 2.048 MHz
  gain: 300,                  # 30.0 dB (gains are in tenths of dB)
  freq_correction: 15,        # 15 PPM frequency correction
  agc_mode: false,           # Disable AGC
  test_mode: false,          # Disable test mode
  bias_tee: false            # Disable bias tee
)

# Or configure individually
device.center_freq = 433_920_000
device.sample_rate = 2_048_000
device.manual_gain_mode!        # Enable manual gain
device.tuner_gain = 300         # 30.0 dB

# Check available gains
puts device.tuner_gains.map { |g| g / 10.0 }  # [0.0, 0.9, 1.4, 2.7, ...]
```

### Reading Samples

```ruby
# Synchronous reading
samples = device.read_samples(4096)  # Returns array of Complex numbers

# Asynchronous reading
device.read_samples_async do |samples|
  # Process samples in real-time
  power = RTLSDR::DSP.average_power(samples)
  puts "Power: #{10 * Math.log10(power + 1e-10)} dB"
end

# Stop async reading
device.cancel_async

# Enumerable interface - read continuously
device.each(samples_per_read: 1024) do |samples|
  # Process each batch of samples
  break if some_condition
end
```

## Signal Processing

The gem includes built-in DSP functions:

```ruby
samples = device.read_samples(8192)

# Power calculations
avg_power = RTLSDR::DSP.average_power(samples)
power_db = 10 * Math.log10(avg_power + 1e-10)

# Convert to magnitude and phase
magnitude = RTLSDR::DSP.magnitude(samples)
phase = RTLSDR::DSP.phase(samples)

# Remove DC component
filtered = RTLSDR::DSP.remove_dc(samples)

# Frequency estimation
freq_offset = RTLSDR::DSP.estimate_frequency(samples, device.sample_rate)

# Power spectrum (simple implementation)
power_spectrum = RTLSDR::DSP.power_spectrum(samples, 1024)
peak_bin, peak_power = RTLSDR::DSP.find_peak(power_spectrum)
```

## Frequency Scanning

Scan frequency ranges to find active signals:

```ruby
# Create a scanner
scanner = RTLSDR::Scanner.new(device,
  start_freq: 88_000_000,      # 88 MHz
  end_freq: 108_000_000,       # 108 MHz
  step_size: 200_000,          # 200 kHz steps
  dwell_time: 0.1              # 100ms per frequency
)

# Perform power sweep
results = scanner.power_sweep(samples_per_freq: 2048)
results.each do |freq, power_db|
  puts "#{freq/1e6} MHz: #{power_db} dB" if power_db > -60
end

# Find peaks above threshold
peaks = scanner.find_peaks(threshold: -50, samples_per_freq: 4096)
peaks.each do |peak|
  puts "#{peak[:frequency]/1e6} MHz: #{peak[:power_db]} dB"
end

# Real-time scanning with callback
scanner.scan(samples_per_freq: 1024) do |result|
  if result[:power] > some_threshold
    puts "Signal found at #{result[:frequency]/1e6} MHz"
  end
end
```

## Advanced Features

### EEPROM Access

```ruby
# Read EEPROM
data = device.read_eeprom(0, 256)  # Read 256 bytes from offset 0

# Write EEPROM (be careful!)
device.write_eeprom([0x01, 0x02, 0x03], 0)  # Write 3 bytes at offset 0
```

### Crystal Frequency Adjustment

```ruby
# Set custom crystal frequencies
device.set_xtal_freq(28_800_000, 28_800_000)  # RTL and tuner crystal freqs

# Get current crystal frequencies
rtl_freq, tuner_freq = device.xtal_freq
```

### Direct Sampling Mode

```ruby
# Enable direct sampling (for HF reception)
device.direct_sampling = 1  # I-ADC input
device.direct_sampling = 2  # Q-ADC input
device.direct_sampling = 0  # Disabled
```

### Bias Tee Control

```ruby
# Enable bias tee on GPIO 0
device.bias_tee = true

# Enable bias tee on specific GPIO
device.set_bias_tee_gpio(1, true)
```

## Error Handling

The gem provides specific exception types:

```ruby
begin
  device = RTLSDR.open(99)  # Non-existent device
rescue RTLSDR::DeviceNotFoundError => e
  puts "Device not found: #{e.message}"
rescue RTLSDR::DeviceOpenError => e
  puts "Could not open device: #{e.message}"
rescue RTLSDR::Error => e
  puts "RTL-SDR error: #{e.message}"
end
```

Exception types:

- `RTLSDR::Error` - Base error class
- `RTLSDR::DeviceNotFoundError` - Device doesn't exist
- `RTLSDR::DeviceOpenError` - Can't open device (in use, permissions, etc.)
- `RTLSDR::DeviceNotOpenError` - Device is not open
- `RTLSDR::InvalidArgumentError` - Invalid parameter
- `RTLSDR::OperationFailedError` - Operation failed
- `RTLSDR::EEPROMError` - EEPROM access error

## Examples

See the `examples/` directory for complete examples:

- `basic_usage.rb` - Basic device control and sample reading
- `spectrum_analyzer.rb` - Advanced spectrum analysis and scanning

Run examples:

```bash
ruby examples/basic_usage.rb
ruby examples/spectrum_analyzer.rb
```

## API Reference

### Module Methods

- `RTLSDR.device_count` - Number of connected devices
- `RTLSDR.device_name(index)` - Get device name
- `RTLSDR.device_usb_strings(index)` - Get USB strings
- `RTLSDR.find_device_by_serial(serial)` - Find device by serial number
- `RTLSDR.open(index)` - Open device and return Device instance
- `RTLSDR.devices` - List all devices with info

### Device Methods

#### Device Control

- `#open?`, `#closed?` - Check device state
- `#close` - Close device
- `#configure(options)` - Configure multiple settings at once
- `#info` - Get device information hash

#### Frequency Control

- `#center_freq`, `#center_freq=` - Center frequency (Hz)
- `#frequency`, `#frequency=` - Alias for center_freq
- `#freq_correction`, `#freq_correction=` - Frequency correction (PPM)
- `#set_xtal_freq(rtl_freq, tuner_freq)` - Set crystal frequencies
- `#xtal_freq` - Get crystal frequencies

#### Gain Control

- `#tuner_gains` - Available gain values (tenths of dB)
- `#tuner_gain`, `#tuner_gain=` - Current gain (tenths of dB)
- `#gain`, `#gain=` - Alias for tuner_gain
- `#tuner_gain_mode=` - Set manual (true) or auto (false) gain
- `#manual_gain_mode!`, `#auto_gain_mode!` - Convenience methods
- `#set_tuner_if_gain(stage, gain)` - Set IF gain for specific stage
- `#tuner_bandwidth=` - Set tuner bandwidth

#### Sample Rate and Modes

- `#sample_rate`, `#sample_rate=` - Sample rate (Hz)
- `#test_mode=`, `#test_mode!` - Enable test mode
- `#agc_mode=`, `#agc_mode!` - Enable AGC
- `#direct_sampling`, `#direct_sampling=` - Direct sampling mode
- `#offset_tuning`, `#offset_tuning=`, `#offset_tuning!` - Offset tuning
- `#bias_tee=`, `#bias_tee!` - Bias tee control
- `#set_bias_tee_gpio(gpio, enabled)` - GPIO-specific bias tee

#### Sample Reading

- `#read_samples(count)` - Read complex samples synchronously
- `#read_sync(length)` - Read raw bytes synchronously
- `#read_samples_async(&block)` - Read samples asynchronously
- `#read_async(&block)` - Read raw bytes asynchronously
- `#cancel_async` - Stop async reading
- `#streaming?` - Check if async reading is active
- `#reset_buffer` - Reset device buffer
- `#each(options, &block)` - Enumerable interface

#### EEPROM Access

- `#read_eeprom(offset, length)` - Read EEPROM data
- `#write_eeprom(data, offset)` - Write EEPROM data

### DSP Functions

- `RTLSDR::DSP.iq_to_complex(data)` - Convert IQ bytes to complex samples
- `RTLSDR::DSP.average_power(samples)` - Calculate average power
- `RTLSDR::DSP.power_spectrum(samples, window_size)` - Power spectrum
- `RTLSDR::DSP.find_peak(power_spectrum)` - Find peak in spectrum
- `RTLSDR::DSP.remove_dc(samples, alpha)` - DC removal filter
- `RTLSDR::DSP.magnitude(samples)` - Convert to magnitude
- `RTLSDR::DSP.phase(samples)` - Extract phase information
- `RTLSDR::DSP.estimate_frequency(samples, sample_rate)` - Frequency estimation

### Scanner Class

- `Scanner.new(device, options)` - Create frequency scanner
- `#scan(&block)` - Perform frequency sweep with callback
- `#scan_async(&block)` - Async frequency sweep
- `#power_sweep(options)` - Get power measurements across frequencies
- `#find_peaks(options)` - Find signal peaks above threshold
- `#stop` - Stop scanning
- `#configure(options)` - Update scan parameters

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write tests for your changes
4. Make sure all tests pass (`rake spec`)
5. Commit your changes (`git commit -am 'Add some feature'`)
6. Push to the branch (`git push origin my-new-feature`)
7. Create a Pull Request

## License

This gem is licensed under the MIT license.

## Requirements

- Ruby 2.7 or later
- librtlsdr (installed system-wide or built locally)
- FFI gem

## Supported Platforms

- Linux (tested on Ubuntu)
- macOS (tested on macOS 10.15+)
- Windows (should work but not extensively tested)

## Credits

This gem provides Ruby bindings for [librtlsdr](https://github.com/steve-m/librtlsdr), the excellent RTL-SDR library by Steve Markgraf and contributors.
