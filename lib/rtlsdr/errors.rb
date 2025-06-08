# frozen_string_literal: true

module RTLSDR
  # Base error class for all RTL-SDR related exceptions
  #
  # This is the parent class for all RTL-SDR specific errors. It extends
  # Ruby's StandardError and provides a consistent error hierarchy for
  # the gem. All other RTL-SDR errors inherit from this class.
  #
  # @since 0.1.0
  class Error < StandardError; end

  # Raised when a requested device cannot be found
  #
  # This exception is thrown when attempting to open or access a device
  # by index that doesn't exist, or when a device with a specific serial
  # number cannot be located.
  #
  # @since 0.1.0
  class DeviceNotFoundError < Error; end

  # Raised when a device cannot be opened
  #
  # This exception occurs when a device exists but cannot be opened,
  # typically because it's already in use by another process or the
  # user lacks sufficient permissions.
  #
  # @since 0.1.0
  class DeviceOpenError < Error; end

  # Raised when attempting to use a device that hasn't been opened
  #
  # This exception is thrown when trying to perform operations on a
  # device that has been closed or was never properly opened.
  #
  # @since 0.1.0
  class DeviceNotOpenError < Error; end

  # Raised when invalid arguments are passed to device functions
  #
  # This exception occurs when function parameters are out of range,
  # of the wrong type, or otherwise invalid for the requested operation.
  #
  # @since 0.1.0
  class InvalidArgumentError < Error; end

  # Raised when a device operation fails
  #
  # This is a general exception for operations that fail at the hardware
  # or driver level, such as setting frequencies, gains, or sample rates
  # that the device cannot support.
  #
  # @since 0.1.0
  class OperationFailedError < Error; end

  # Raised when EEPROM operations fail
  #
  # This exception occurs when reading from or writing to the device's
  # EEPROM memory fails, either due to hardware issues or invalid
  # memory addresses.
  #
  # @since 0.1.0
  class EEPROMError < Error; end

  # Raised when asynchronous callback operations fail
  #
  # This exception is thrown when errors occur within the async reading
  # callback functions, typically during real-time sample processing.
  #
  # @since 0.1.0
  class CallbackError < Error; end
end
