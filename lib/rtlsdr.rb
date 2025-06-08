# frozen_string_literal: true

require_relative "rtlsdr/version"
require_relative "rtlsdr/ffi"
require_relative "rtlsdr/device"
require_relative "rtlsdr/errors"
require_relative "rtlsdr/dsp"
require_relative "rtlsdr/scanner"

# Ruby bindings for RTL-SDR (Software Defined Radio) devices
#
# RTLSDR provides a complete Ruby interface to RTL-SDR USB dongles, enabling
# software-defined radio applications. It offers both low-level FFI bindings
# that map directly to the librtlsdr C API and high-level Ruby classes with
# idiomatic methods and DSLs.
#
# Features:
# * Device enumeration and control
# * Frequency, gain, and sample rate configuration
# * Synchronous and asynchronous sample reading
# * Signal processing utilities (DSP)
# * Frequency scanning and spectrum analysis
# * EEPROM reading/writing and bias tee control
#
# @example Basic usage
#   device = RTLSDR.open(0)
#   device.sample_rate = 2_048_000
#   device.center_freq = 100_000_000
#   device.gain = 496
#   samples = device.read_samples(1024)
#   device.close
#
# @example List all devices
#   RTLSDR.devices.each do |dev|
#     puts "#{dev[:index]}: #{dev[:name]}"
#   end
module RTLSDR
  class << self
    # Get the number of connected RTL-SDR devices
    #
    # @return [Integer] Number of RTL-SDR devices found
    # @example Check for devices
    #   if RTLSDR.device_count > 0
    #     puts "Found #{RTLSDR.device_count} RTL-SDR devices"
    #   end
    def device_count
      FFI.rtlsdr_get_device_count
    end

    # Get the name of a device by index
    #
    # @param [Integer] index Device index (0-based)
    # @return [String] Device name string
    # @example Get device name
    #   name = RTLSDR.device_name(0)
    #   puts "Device 0: #{name}"
    def device_name(index)
      FFI.rtlsdr_get_device_name(index)
    end

    # Get USB device strings for a device by index
    #
    # Retrieves the USB manufacturer, product, and serial number strings
    # for the specified device.
    #
    # @param [Integer] index Device index (0-based)
    # @return [Hash, nil] Hash with :manufacturer, :product, :serial keys, or nil on error
    # @example Get USB info
    #   usb_info = RTLSDR.device_usb_strings(0)
    #   puts "#{usb_info[:manufacturer]} #{usb_info[:product]}"
    def device_usb_strings(index)
      manufact = " " * 256
      product = " " * 256
      serial = " " * 256

      result = FFI.rtlsdr_get_device_usb_strings(index, manufact, product, serial)
      return nil if result != 0

      {
        manufacturer: manufact.strip,
        product: product.strip,
        serial: serial.strip
      }
    end

    # Find device index by serial number
    #
    # Searches for a device with the specified serial number and returns
    # its index if found.
    #
    # @param [String] serial Serial number to search for
    # @return [Integer, nil] Device index if found, nil otherwise
    # @example Find device by serial
    #   index = RTLSDR.find_device_by_serial("00000001")
    #   device = RTLSDR.open(index) if index
    def find_device_by_serial(serial)
      result = FFI.rtlsdr_get_index_by_serial(serial)
      return nil if result.negative?

      result
    end

    # Open a device and return a Device instance
    #
    # Creates and returns a new Device instance for the specified device index.
    # The device will be automatically opened and ready for use.
    #
    # @param [Integer] index Device index to open (default: 0)
    # @return [RTLSDR::Device] Device instance
    # @raise [DeviceNotFoundError] if device doesn't exist
    # @raise [DeviceOpenError] if device cannot be opened
    # @example Open first device
    #   device = RTLSDR.open(0)
    #   device.center_freq = 100_000_000
    def open(index = 0)
      Device.new(index)
    end

    # List all available devices with their information
    #
    # Returns an array of hashes containing information about all connected
    # RTL-SDR devices, including index, name, and USB strings.
    #
    # @return [Array<Hash>] Array of device information hashes
    # @example List all devices
    #   RTLSDR.devices.each do |device|
    #     puts "#{device[:index]}: #{device[:name]}"
    #     puts "  #{device[:usb_strings][:manufacturer]} #{device[:usb_strings][:product]}"
    #   end
    def devices
      (0...device_count).map do |i|
        {
          index: i,
          name: device_name(i),
          usb_strings: device_usb_strings(i)
        }
      end
    end
  end
end
