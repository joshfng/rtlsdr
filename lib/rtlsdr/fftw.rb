# frozen_string_literal: true

module RTLSDR
  # FFI bindings for FFTW3 (Fastest Fourier Transform in the West)
  #
  # This module provides low-level FFI bindings to the FFTW3 library for
  # performing fast Fourier transforms. FFTW3 must be installed on the system.
  #
  # @note This is an internal module. Use RTLSDR::DSP.fft and related methods instead.
  #
  # @example System installation
  #   # macOS: brew install fftw
  #   # Ubuntu/Debian: apt-get install libfftw3-dev
  #   # Fedora: dnf install fftw-devel
  module FFTW
    extend ::FFI::Library

    # Try to load FFTW3 library with common paths
    LIBRARY_NAMES = %w[
      fftw3
      libfftw3.so.3
      libfftw3.dylib
      libfftw3-3.dll
    ].freeze

    begin
      ffi_lib LIBRARY_NAMES
      @available = true
    rescue LoadError => e
      @available = false
      @load_error = e.message
    end

    class << self
      # Check if FFTW3 library is available
      #
      # @return [Boolean] true if FFTW3 is loaded and available
      def available?
        @available
      end

      # Get the error message if FFTW3 failed to load
      #
      # @return [String, nil] Error message or nil if loaded successfully
      attr_reader :load_error
    end

    # FFTW planning flags
    FFTW_MEASURE = 0
    FFTW_DESTROY_INPUT = 1
    FFTW_UNALIGNED = 2
    FFTW_CONSERVE_MEMORY = 4
    FFTW_EXHAUSTIVE = 8
    FFTW_PRESERVE_INPUT = 16
    FFTW_PATIENT = 32
    FFTW_ESTIMATE = 64
    FFTW_WISDOM_ONLY = 2_097_152

    # FFT direction
    FFTW_FORWARD = -1
    FFTW_BACKWARD = 1

    if available?
      # Memory allocation
      attach_function :fftw_malloc, [:size_t], :pointer
      attach_function :fftw_free, [:pointer], :void

      # Plan creation and execution
      attach_function :fftw_plan_dft_1d, %i[int pointer pointer int uint], :pointer
      attach_function :fftw_execute, [:pointer], :void
      attach_function :fftw_destroy_plan, [:pointer], :void

      # Wisdom (plan caching)
      attach_function :fftw_export_wisdom_to_string, [], :pointer
      attach_function :fftw_import_wisdom_from_string, [:string], :int
      attach_function :fftw_forget_wisdom, [], :void
    end

    # Size of a complex number in FFTW (two doubles)
    COMPLEX_SIZE = 16

    # Perform forward FFT on complex samples
    #
    # @param [Array<Complex>] samples Input complex samples
    # @return [Array<Complex>] FFT result (complex frequency bins)
    # @raise [RuntimeError] if FFTW3 is not available
    def self.forward(samples)
      raise "FFTW3 library not available: #{load_error}" unless available?

      n = samples.length
      return [] if n.zero?

      # Allocate input and output arrays
      input = fftw_malloc(n * COMPLEX_SIZE)
      output = fftw_malloc(n * COMPLEX_SIZE)

      begin
        # Copy samples to input array (interleaved real/imag doubles)
        samples.each_with_index do |sample, i|
          input.put_float64(i * COMPLEX_SIZE, sample.real)
          input.put_float64((i * COMPLEX_SIZE) + 8, sample.imag)
        end

        # Create and execute plan
        plan = fftw_plan_dft_1d(n, input, output, FFTW_FORWARD, FFTW_ESTIMATE)
        raise "Failed to create FFTW plan" if plan.null?

        begin
          fftw_execute(plan)

          # Read output into Ruby Complex array
          result = Array.new(n) do |i|
            real = output.get_float64(i * COMPLEX_SIZE)
            imag = output.get_float64((i * COMPLEX_SIZE) + 8)
            Complex(real, imag)
          end

          result
        ensure
          fftw_destroy_plan(plan)
        end
      ensure
        fftw_free(input)
        fftw_free(output)
      end
    end

    # Perform inverse FFT on complex spectrum
    #
    # @param [Array<Complex>] spectrum Input complex spectrum
    # @return [Array<Complex>] IFFT result (time domain samples)
    # @raise [RuntimeError] if FFTW3 is not available
    def self.backward(spectrum)
      raise "FFTW3 library not available: #{load_error}" unless available?

      n = spectrum.length
      return [] if n.zero?

      # Allocate input and output arrays
      input = fftw_malloc(n * COMPLEX_SIZE)
      output = fftw_malloc(n * COMPLEX_SIZE)

      begin
        # Copy spectrum to input array
        spectrum.each_with_index do |sample, i|
          input.put_float64(i * COMPLEX_SIZE, sample.real)
          input.put_float64((i * COMPLEX_SIZE) + 8, sample.imag)
        end

        # Create and execute plan
        plan = fftw_plan_dft_1d(n, input, output, FFTW_BACKWARD, FFTW_ESTIMATE)
        raise "Failed to create FFTW plan" if plan.null?

        begin
          fftw_execute(plan)

          # Read output and normalize (FFTW doesn't normalize IFFT)
          result = Array.new(n) do |i|
            real = output.get_float64(i * COMPLEX_SIZE) / n
            imag = output.get_float64((i * COMPLEX_SIZE) + 8) / n
            Complex(real, imag)
          end

          result
        ensure
          fftw_destroy_plan(plan)
        end
      ensure
        fftw_free(input)
        fftw_free(output)
      end
    end
  end
end
