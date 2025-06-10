# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "rdoc/task"
require "yard"

# rubocop:disable Metrics/BlockLength

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new

# RDoc documentation generation
RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = "doc"
  rdoc.title = "RTL-SDR Ruby Gem Documentation"
  rdoc.main = "README.md"
  rdoc.rdoc_files.include("README.md", "CHANGELOG.md", "LICENSE.txt", "lib/**/*.rb")

  # RDoc options for better output
  rdoc.options << "--line-numbers"
  rdoc.options << "--all"
  rdoc.options << "--charset=UTF-8"
  rdoc.options << "--exclude=spec/"
  rdoc.options << "--exclude=examples/"
  rdoc.options << "--exclude=bin/"
  rdoc.options << "--exclude=exe/"
  rdoc.options << "--template=hanna" if system("gem list hanna -i > /dev/null 2>&1")
end

# Clean documentation
desc "Remove generated documentation"
task :clean_doc do
  rm_rf "doc"
end

YARD::Rake::YardocTask.new(:yard) do |yard|
  yard.files = ["lib/**/*.rb", "-", "README.md", "CHANGELOG.md", "LICENSE.txt"]
  yard.options = [
    "--output-dir", "doc",
    "--readme", "README.md",
    "--title", "RTL-SDR Ruby Gem Documentation",
    "--markup", "markdown",
    "--markup-provider", "redcarpet",
    "--protected",
    "--no-private",
    "--embed-mixins"
  ]
end

# YARD server for live documentation browsing
desc "Start YARD documentation server"
task :yard_server do
  system("yard server --reload")
end

# YARD statistics
desc "Show YARD documentation statistics"
task :yard_stats do
  system("yard stats")
end

# Generate YARD documentation with coverage report
desc "Generate YARD docs with coverage report"
task :yard_coverage do
  puts "Generating YARD documentation with coverage report..."
  system("yard doc")

  # Parse YARD output for coverage
  if system("yard stats > /tmp/yard_stats.txt 2>&1")
    stats = File.read("/tmp/yard_stats.txt")
    if stats =~ /(\d+\.\d+)% documented/
      coverage = Regexp.last_match(1).to_f
      puts "\nYARD Documentation coverage: #{coverage}%"

      if coverage < 90.0
        puts "WARNING: YARD documentation coverage is below 90%"
        exit 1 if ENV["REQUIRE_DOC_COVERAGE"]
      else
        puts "✓ YARD documentation coverage is good!"
      end
    end
  end
end

# Comprehensive documentation check
desc "Check documentation coverage and quality"
task :doc_check do
  puts "Running RDoc to check documentation coverage..."
  system("rdoc --verbose lib/ > /tmp/rdoc_output.txt 2>&1")

  # Parse output for coverage info
  if File.exist?("/tmp/rdoc_output.txt")
    output = File.read("/tmp/rdoc_output.txt")
    if output =~ /(\d+\.\d+)% documented/
      coverage = Regexp.last_match(1).to_f
      puts "Documentation coverage: #{coverage}%"

      if coverage < 90.0
        puts "WARNING: Documentation coverage is below 90%"
        exit 1 if ENV["REQUIRE_DOC_COVERAGE"]
      else
        puts "✓ Documentation coverage is good!"
      end
    end

    # Check for undocumented items
    if output.include?("undocumented")
      puts "\nUndocumented items found:"
      output.scan(/(\S+) \(undocumented\)/).each { |match| puts "  - #{match[0]}" }
    end
  end
end

# Documentation tasks
desc "Generate all documentation (RDoc and YARD)"
task docs: %i[rdoc yard]

desc "Check all documentation coverage"
task doc_coverage: %i[doc_check yard_coverage]

desc "Clean all generated documentation"
task clean_docs: [:clean_doc] do
  rm_rf "doc"
  rm_rf ".yardoc"
end

desc "Serve documentation locally"
task :serve_docs do
  puts "Choose documentation format:"
  puts "1. RDoc (file://#{Dir.pwd}/doc/index.html)"
  puts "2. YARD server (http://localhost:8808)"
  print "Enter choice (1-2): "

  choice = $stdin.gets.chomp
  case choice
  when "1"
    Rake::Task[:rdoc].invoke unless File.exist?("doc/index.html")
    system("open doc/index.html") if RUBY_PLATFORM =~ /darwin/
    puts "RDoc documentation: file://#{Dir.pwd}/doc/index.html"
  when "2"
    Rake::Task[:yard_server].invoke
  else
    puts "Invalid choice"
  end
end

task default: %i[spec rubocop doc_check]

# Task to help users install librtlsdr
desc "Check for librtlsdr or provide installation instructions"
task :check_librtlsdr do
  puts "Checking for librtlsdr installation..."

  # Try to load the library to check if it's available
  begin
    require_relative "lib/rtlsdr/ffi"
    puts "✓ librtlsdr found and loadable"
  rescue LoadError => e
    puts "✗ librtlsdr not found"
    puts
    puts "To install librtlsdr:"
    puts "  Ubuntu/Debian: sudo apt-get install librtlsdr-dev"
    puts "  macOS:         brew install librtlsdr"
    puts "  Windows:       See https://github.com/steve-m/librtlsdr for build instructions"
    puts
    puts "Or build from source:"
    puts "  git clone https://github.com/steve-m/librtlsdr.git"
    puts "  cd librtlsdr && mkdir build && cd build"
    puts "  cmake .. && make && sudo make install"
    puts
    puts "Error details: #{e.message}"
    exit 1
  end
end

desc "Bump version, update CHANGELOG, commit, tag, and push"
task :publish_release do
  puts "Make sure you have committed all your changes before running this task."
  puts "Do you want to continue? (yes/no)"

  answer = $stdin.gets.chomp.downcase
  if answer == "yes"
    Rake::Task["version:patch"].invoke

    # Read the updated version from file since RTLSDR::VERSION is cached
    version_content = File.read("lib/rtlsdr/version.rb")
    new_version = version_content.match(/VERSION = "([^"]+)"/)[1]

    puts "Hit enter when you've updated the CHANGELOG"
    $stdin.gets.chomp.downcase

    puts "Committing changes..."
    system("git add -A")
    system("git commit -m 'Bump version to #{new_version}'")
    puts "Creating git tag..."
    system("git tag v#{new_version}")
    puts "Pushing changes and tags to remote repository..."
    system("git push && git push --tags")
    puts "Release process completed successfully!"

    Rake::Task["release"].invoke
  else
    puts "Release process aborted."
  end
end

# Version management tasks
namespace :version do
  desc "Bump patch version (x.y.z -> x.y.z+1)"
  task :patch do
    bump_version(:patch)
  end

  desc "Bump minor version (x.y.z -> x.y+1.0)"
  task :minor do
    bump_version(:minor)
  end

  desc "Bump major version (x.y.z -> x+1.0.0)"
  task :major do
    bump_version(:major)
  end

  desc "Show current version"
  task :show do
    require_relative "lib/rtlsdr/version"
    puts "Current version: #{RTLSDR::VERSION}"
  end
end

desc "Bump patch version (shortcut for version:patch)"
task :bump do
  Rake::Task["version:patch"].invoke
end

def bump_version(type) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
  version_file = "lib/rtlsdr/version.rb"
  content = File.read(version_file)

  # Extract current version
  current_version = content.match(/VERSION = "([^"]+)"/)[1]
  major, minor, patch = current_version.split(".").map(&:to_i)

  # Calculate new version based on type
  case type
  when :patch
    patch += 1
  when :minor
    minor += 1
    patch = 0
  when :major
    major += 1
    minor = 0
    patch = 0
  end

  new_version = "#{major}.#{minor}.#{patch}"

  # Update version file
  new_content = content.gsub(/VERSION = "#{Regexp.escape(current_version)}"/, %(VERSION = "#{new_version}"))
  File.write(version_file, new_content)

  # Update Gemfile.lock if it exists
  if File.exist?("Gemfile.lock")
    gemfile_lock = File.read("Gemfile.lock")
    updated_gemfile_lock = gemfile_lock.gsub(/rtlsdr \(#{Regexp.escape(current_version)}\)/, "rtlsdr (#{new_version})")
    File.write("Gemfile.lock", updated_gemfile_lock)
    puts "Updated Gemfile.lock"
  end

  puts "Version bumped from #{current_version} to #{new_version}"

  # Update CHANGELOG if it exists
  return unless File.exist?("CHANGELOG.md")

  changelog = File.read("CHANGELOG.md")
  date = Time.now.strftime("%Y-%m-%d")

  # Add new version entry at the top after the header
  new_entry = "\n## [#{new_version}] - #{date}\n\n### Added\n\n### Changed\n\n### Fixed\n\n"

  updated_changelog = if changelog.include?("## [Unreleased]")
                        # Insert after Unreleased section
                        changelog.sub(/(## \[Unreleased\].*?\n)/, "\\1#{new_entry}")
                      elsif changelog.include?("# Changelog")
                        # Insert after main header
                        changelog.sub(/(# Changelog\s*\n)/, "\\1#{new_entry}")
                      else
                        # Prepend to file if no standard structure
                        "# Changelog#{new_entry}#{changelog}"
                      end

  File.write("CHANGELOG.md", updated_changelog)
  puts "Updated CHANGELOG.md with new version entry"
end

# rubocop:enable Metrics/BlockLength
