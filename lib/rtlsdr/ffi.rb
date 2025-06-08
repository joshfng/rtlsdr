# frozen_string_literal: true

require "ffi"

module RTLSDR
  # Low-level FFI bindings to librtlsdr
  #
  # The FFI module provides direct 1:1 bindings to the librtlsdr C library,
  # exposing all native functions with their original signatures and behaviors.
  # This module handles library loading from multiple common locations and
  # defines all necessary data types, constants, and function prototypes.
  #
  # This is the foundation layer that the high-level Device class is built upon,
  # but can also be used directly for applications that need complete control
  # over the C API or want to implement custom abstractions.
  #
  # Features:
  # * Complete librtlsdr API coverage
  # * Automatic library discovery and loading
  # * Proper FFI type definitions and callbacks
  # * Tuner type constants and helper functions
  # * Memory management support for pointers
  #
  # @example Direct FFI usage
  #   device_count = RTLSDR::FFI.rtlsdr_get_device_count
  #   device_ptr = FFI::MemoryPointer.new(:pointer)
  #   result = RTLSDR::FFI.rtlsdr_open(device_ptr, 0)
  #   handle = device_ptr.read_pointer
  #   RTLSDR::FFI.rtlsdr_set_center_freq(handle, 100_000_000)
  #
  # @note Most users should use the high-level RTLSDR::Device class instead
  #   of calling these FFI functions directly.
  # @since 0.1.0
  module FFI
    extend ::FFI::Library

    # Try to load the library from various locations
    begin
      ffi_lib "rtlsdr"
    rescue LoadError
      begin
        ffi_lib "./librtlsdr/build/install/lib/librtlsdr.so"
      rescue LoadError
        begin
          ffi_lib "/usr/local/lib/librtlsdr.so"
        rescue LoadError
          begin
            ffi_lib "/usr/lib/librtlsdr.so"
          rescue LoadError # rubocop:disable Metrics/BlockNesting
            raise LoadError,
                  "Could not find librtlsdr. Make sure it's installed or built in librtlsdr/build/install/lib/"
          end
        end
      end
    end

    # Opaque device pointer
    typedef :pointer, :rtlsdr_dev_t

    # Tuner types enum constants
    #
    # These constants identify the different tuner chips that can be found
    # in RTL-SDR devices. Each tuner has different characteristics and
    # supported frequency ranges.

    # Unknown or unsupported tuner type
    RTLSDR_TUNER_UNKNOWN = 0
    # Elonics E4000 tuner (52 - 2200 MHz with gaps)
    RTLSDR_TUNER_E4000 = 1
    # Fitipower FC0012 tuner (22 - 948 MHz)
    RTLSDR_TUNER_FC0012 = 2
    # Fitipower FC0013 tuner (22 - 1100 MHz)
    RTLSDR_TUNER_FC0013 = 3
    # FCI FC2580 tuner (146 - 308 MHz and 438 - 924 MHz)
    RTLSDR_TUNER_FC2580 = 4
    # Rafael Micro R820T tuner (24 - 1766 MHz)
    RTLSDR_TUNER_R820T = 5
    # Rafael Micro R828D tuner (24 - 1766 MHz)
    RTLSDR_TUNER_R828D = 6

    # Callback function type for asynchronous reading
    #
    # This callback is called by the C library when new sample data is available
    # during asynchronous reading operations. The callback receives a pointer to
    # the buffer data, the length of the buffer, and a user context pointer.
    callback :rtlsdr_read_async_cb_t, %i[pointer uint32 pointer], :void

    # Device enumeration functions

    # Get the number of available RTL-SDR devices
    attach_function :rtlsdr_get_device_count, [], :uint32

    # Get the name of an RTL-SDR device by index
    attach_function :rtlsdr_get_device_name, [:uint32], :string

    # Get USB device strings (manufacturer, product, serial)
    attach_function :rtlsdr_get_device_usb_strings, %i[uint32 pointer pointer pointer], :int

    # Find device index by serial number
    attach_function :rtlsdr_get_index_by_serial, [:string], :int

    # Device control functions

    # Open an RTL-SDR device
    attach_function :rtlsdr_open, %i[pointer uint32], :int

    # Close an RTL-SDR device
    attach_function :rtlsdr_close, [:rtlsdr_dev_t], :int

    # Configuration functions
    attach_function :rtlsdr_set_xtal_freq, %i[rtlsdr_dev_t uint32 uint32], :int
    attach_function :rtlsdr_get_xtal_freq, %i[rtlsdr_dev_t pointer pointer], :int
    attach_function :rtlsdr_get_usb_strings, %i[rtlsdr_dev_t pointer pointer pointer], :int
    attach_function :rtlsdr_write_eeprom, %i[rtlsdr_dev_t pointer uint8 uint16], :int
    attach_function :rtlsdr_read_eeprom, %i[rtlsdr_dev_t pointer uint8 uint16], :int

    # Frequency control
    attach_function :rtlsdr_set_center_freq, %i[rtlsdr_dev_t uint32], :int
    attach_function :rtlsdr_get_center_freq, [:rtlsdr_dev_t], :uint32
    attach_function :rtlsdr_set_freq_correction, %i[rtlsdr_dev_t int], :int
    attach_function :rtlsdr_get_freq_correction, [:rtlsdr_dev_t], :int

    # Tuner functions
    attach_function :rtlsdr_get_tuner_type, [:rtlsdr_dev_t], :int
    attach_function :rtlsdr_get_tuner_gains, %i[rtlsdr_dev_t pointer], :int
    attach_function :rtlsdr_set_tuner_gain, %i[rtlsdr_dev_t int], :int
    attach_function :rtlsdr_set_tuner_bandwidth, %i[rtlsdr_dev_t uint32], :int
    attach_function :rtlsdr_get_tuner_gain, [:rtlsdr_dev_t], :int
    attach_function :rtlsdr_set_tuner_if_gain, %i[rtlsdr_dev_t int int], :int
    attach_function :rtlsdr_set_tuner_gain_mode, %i[rtlsdr_dev_t int], :int

    # Sample rate and mode functions
    attach_function :rtlsdr_set_sample_rate, %i[rtlsdr_dev_t uint32], :int
    attach_function :rtlsdr_get_sample_rate, [:rtlsdr_dev_t], :uint32
    attach_function :rtlsdr_set_testmode, %i[rtlsdr_dev_t int], :int
    attach_function :rtlsdr_set_agc_mode, %i[rtlsdr_dev_t int], :int
    attach_function :rtlsdr_set_direct_sampling, %i[rtlsdr_dev_t int], :int
    attach_function :rtlsdr_get_direct_sampling, [:rtlsdr_dev_t], :int
    attach_function :rtlsdr_set_offset_tuning, %i[rtlsdr_dev_t int], :int
    attach_function :rtlsdr_get_offset_tuning, [:rtlsdr_dev_t], :int

    # Streaming functions
    attach_function :rtlsdr_reset_buffer, [:rtlsdr_dev_t], :int
    attach_function :rtlsdr_read_sync, %i[rtlsdr_dev_t pointer int pointer], :int
    attach_function :rtlsdr_wait_async, %i[rtlsdr_dev_t rtlsdr_read_async_cb_t pointer], :int
    attach_function :rtlsdr_read_async, %i[rtlsdr_dev_t rtlsdr_read_async_cb_t pointer uint32 uint32], :int
    attach_function :rtlsdr_cancel_async, [:rtlsdr_dev_t], :int

    # Bias tee functions
    attach_function :rtlsdr_set_bias_tee, %i[rtlsdr_dev_t int], :int
    attach_function :rtlsdr_set_bias_tee_gpio, %i[rtlsdr_dev_t int int], :int

    # Convert tuner type constant to human-readable name
    #
    # @param [Integer] tuner_type One of the RTLSDR_TUNER_* constants
    # @return [String] Human-readable tuner name with chip details
    # @example Get tuner name
    #   RTLSDR::FFI.tuner_type_name(RTLSDR::FFI::RTLSDR_TUNER_R820T)
    #   # => "Rafael Micro R820T"
    def self.tuner_type_name(tuner_type)
      case tuner_type
      when RTLSDR_TUNER_UNKNOWN then "Unknown"
      when RTLSDR_TUNER_E4000 then "Elonics E4000"
      when RTLSDR_TUNER_FC0012 then "Fitipower FC0012"
      when RTLSDR_TUNER_FC0013 then "Fitipower FC0013"
      when RTLSDR_TUNER_FC2580 then "FCI FC2580"
      when RTLSDR_TUNER_R820T then "Rafael Micro R820T"
      when RTLSDR_TUNER_R828D then "Rafael Micro R828D"
      else "Unknown (#{tuner_type})"
      end
    end
  end
end
