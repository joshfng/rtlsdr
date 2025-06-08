# frozen_string_literal: true

# Documentation configuration for RTL-SDR Ruby gem
# This file contains documentation configuration notes

# RDoc Configuration
# The RDoc configuration is handled in the Rakefile RDoc::Task.
# Key settings:
# - Title: "RTL-SDR Ruby Gem Documentation"
# - Main page: README.md
# - Output directory: doc/
# - Includes: README.md, CHANGELOG.md, LICENSE.txt, lib/**/*.rb
# - Excludes: spec/, examples/, bin/, exe/

# YARD Configuration
# YARD configuration is handled via:
# - .yardopts file for command line options
# - .yardconfig file for advanced settings
# - Rakefile YARD::Rake::YardocTask for task configuration

# Documentation Standards
# - 100% documentation coverage required
# - All public methods must have @param and @return tags
# - Examples should be provided using @example
# - Version tracking with @since tags
