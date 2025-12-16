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

### Optional: FFTW3 for FFT Support

To enable FFT features (fast spectrum analysis, frequency response, etc.), install FFTW3:

```bash
# Ubuntu/Debian
sudo apt-get install libfftw3-dev

# macOS
brew install fftw
```

FFT features are optional - the gem works without FFTW3, but FFT-related functions will raise an error if called.

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

### FFT Analysis (requires FFTW3)

```ruby
# Check if FFT is available
if RTLSDR::DSP.fft_available?
  # Forward FFT
  spectrum = RTLSDR::DSP.fft(samples)

  # Power spectrum in dB with windowing
  power_db = RTLSDR::DSP.fft_power_db(samples, window: :hanning)

  # Shift DC to center (like numpy.fft.fftshift)
  centered = RTLSDR::DSP.fft_shift(spectrum)

  # Inverse FFT
  reconstructed = RTLSDR::DSP.ifft(spectrum)
end

# Available window functions: :hanning, :hamming, :blackman, :none
windowed = RTLSDR::DSP.apply_window(samples, :blackman)
```

### Digital Filters

```ruby
# Create lowpass filter (100 kHz cutoff at 2.048 MHz sample rate)
lpf = RTLSDR::DSP::Filter.lowpass(
  cutoff: 100_000,
  sample_rate: 2_048_000,
  taps: 63,
  window: :hamming
)

# Create highpass filter
hpf = RTLSDR::DSP::Filter.highpass(cutoff: 1000, sample_rate: 48_000)

# Create bandpass filter (voice: 300-3000 Hz)
bpf = RTLSDR::DSP::Filter.bandpass(low: 300, high: 3000, sample_rate: 48_000)

# Create bandstop (notch) filter
notch = RTLSDR::DSP::Filter.bandstop(low: 50, high: 60, sample_rate: 48_000)

# Apply filter
filtered = lpf.apply(samples)

# Zero-phase filtering (no phase distortion)
filtered = lpf.apply_zero_phase(samples)

# Get filter properties
puts lpf.group_delay  # Delay in samples
puts lpf.taps         # Number of filter taps

# Get frequency response (requires FFTW3)
response = lpf.frequency_response(256)
```

### Decimation and Resampling

```ruby
# Decimate by factor of 4 (with anti-aliasing filter)
decimated = RTLSDR::DSP.decimate(samples, 4)

# Interpolate by factor of 2
interpolated = RTLSDR::DSP.interpolate(samples, 2)

# Resample from 2.4 MHz to 48 kHz
audio = RTLSDR::DSP.resample(samples, from_rate: 2_400_000, to_rate: 48_000)
```

## Demodulation

The gem includes demodulators for common radio signals:

### FM Demodulation

```ruby
# Wideband FM (broadcast radio 88-108 MHz)
audio = RTLSDR::Demod.fm(samples, sample_rate: 2_048_000, audio_rate: 48_000)

# With European de-emphasis (50µs instead of US 75µs)
audio = RTLSDR::Demod.fm(samples, sample_rate: 2_048_000, tau: 50e-6)

# Narrowband FM (voice radio, ham, FRS)
audio = RTLSDR::Demod.nfm(samples, sample_rate: 2_048_000)
```

### AM Demodulation

```ruby
# Envelope detection (simple AM)
audio = RTLSDR::Demod.am(samples, sample_rate: 2_048_000)

# Synchronous AM (better quality)
audio = RTLSDR::Demod.am_sync(samples, sample_rate: 2_048_000)
```

### SSB Demodulation

```ruby
# Upper Sideband (ham radio above 10 MHz)
audio = RTLSDR::Demod.usb(samples, sample_rate: 2_048_000, bfo_offset: 1500)

# Lower Sideband (ham radio below 10 MHz)
audio = RTLSDR::Demod.lsb(samples, sample_rate: 2_048_000, bfo_offset: 1500)
```

### FSK Demodulation

```ruby
# Demodulate FSK signal at 1200 baud
bits = RTLSDR::Demod.fsk(samples, sample_rate: 48_000, baud_rate: 1200)

# RTTY at 45.45 baud
bits = RTLSDR::Demod.fsk(samples, sample_rate: 48_000, baud_rate: 45.45)

# Invert mark/space if needed
bits = RTLSDR::Demod.fsk(samples, sample_rate: 48_000, baud_rate: 1200, invert: true)

# Get raw discriminator output for debugging/visualization
waveform = RTLSDR::Demod.fsk_raw(samples, sample_rate: 48_000, baud_rate: 1200)
```

### Helper Functions

```ruby
# Generate complex oscillator for mixing
osc = RTLSDR::Demod.complex_oscillator(1024, 1000, 48_000)

# Frequency shift a signal
shifted = RTLSDR::Demod.mix(samples, -10_000, 2_048_000)

# FM discriminator (phase difference)
baseband = RTLSDR::Demod.phase_diff(samples)

# De-emphasis filter for FM audio
filtered = RTLSDR::Demod.deemphasis(audio, 75e-6, 48_000)
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

#### Basic Functions

- `RTLSDR::DSP.iq_to_complex(data)` - Convert IQ bytes to complex samples
- `RTLSDR::DSP.average_power(samples)` - Calculate average power
- `RTLSDR::DSP.power_spectrum(samples, window_size)` - Power spectrum
- `RTLSDR::DSP.find_peak(power_spectrum)` - Find peak in spectrum
- `RTLSDR::DSP.remove_dc(samples, alpha)` - DC removal filter
- `RTLSDR::DSP.magnitude(samples)` - Convert to magnitude
- `RTLSDR::DSP.phase(samples)` - Extract phase information
- `RTLSDR::DSP.estimate_frequency(samples, sample_rate)` - Frequency estimation

#### FFT Functions (requires FFTW3)

- `RTLSDR::DSP.fft_available?` - Check if FFTW3 is available
- `RTLSDR::DSP.fft(samples)` - Forward FFT
- `RTLSDR::DSP.ifft(spectrum)` - Inverse FFT
- `RTLSDR::DSP.fft_power_db(samples, window:)` - Power spectrum in dB
- `RTLSDR::DSP.fft_shift(spectrum)` - Shift DC to center
- `RTLSDR::DSP.ifft_shift(spectrum)` - Reverse fft_shift
- `RTLSDR::DSP.apply_window(samples, type)` - Apply window function

#### Decimation and Resampling

- `RTLSDR::DSP.decimate(samples, factor)` - Decimate with anti-aliasing
- `RTLSDR::DSP.interpolate(samples, factor)` - Interpolate samples
- `RTLSDR::DSP.resample(samples, from_rate:, to_rate:)` - Rational resampling

### Filter Class

- `Filter.lowpass(cutoff:, sample_rate:, taps:, window:)` - Design lowpass filter
- `Filter.highpass(cutoff:, sample_rate:, taps:, window:)` - Design highpass filter
- `Filter.bandpass(low:, high:, sample_rate:, taps:, window:)` - Design bandpass filter
- `Filter.bandstop(low:, high:, sample_rate:, taps:, window:)` - Design bandstop filter
- `#apply(samples)` - Apply filter to samples
- `#apply_zero_phase(samples)` - Zero-phase filtering
- `#frequency_response(points)` - Get filter frequency response
- `#group_delay` - Get filter group delay
- `#coefficients` - Get filter coefficients
- `#taps` - Number of filter taps

### Demod Module

#### FM Demodulation

- `Demod.fm(samples, sample_rate:, audio_rate:, deviation:, tau:)` - Wideband FM
- `Demod.nfm(samples, sample_rate:, audio_rate:, deviation:)` - Narrowband FM

#### AM Demodulation

- `Demod.am(samples, sample_rate:, audio_rate:, audio_bandwidth:)` - Envelope detection
- `Demod.am_sync(samples, sample_rate:, audio_rate:, audio_bandwidth:)` - Synchronous AM

#### SSB Demodulation

- `Demod.usb(samples, sample_rate:, audio_rate:, bfo_offset:)` - Upper Sideband
- `Demod.lsb(samples, sample_rate:, audio_rate:, bfo_offset:)` - Lower Sideband

#### FSK Demodulation

- `Demod.fsk(samples, sample_rate:, baud_rate:, invert:)` - FSK to bits
- `Demod.fsk_raw(samples, sample_rate:, baud_rate:)` - Raw discriminator output

#### Helper Functions

- `Demod.complex_oscillator(length, frequency, sample_rate)` - Generate carrier
- `Demod.mix(samples, frequency, sample_rate)` - Frequency shift signal
- `Demod.phase_diff(samples)` - FM discriminator
- `Demod.deemphasis(samples, tau, sample_rate)` - De-emphasis filter

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

- Ruby 3.3 or later
- librtlsdr (installed system-wide or built locally)
- FFI gem
- libfftw3 (optional, for FFT functions)

## Supported Platforms

- Linux (tested on Ubuntu)
- macOS (tested on macOS 10.15+)
- Windows (should work but not extensively tested)

## Credits

This gem provides Ruby bindings for [librtlsdr](https://github.com/steve-m/librtlsdr), the excellent RTL-SDR library by Steve Markgraf and contributors.
