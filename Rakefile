# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "rdoc/task"
require "yard"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

DOC_TITLE = "RTL-SDR Ruby Gem Documentation"
DOC_FILES = ["lib/**/*.rb", "-", "README.md", "CHANGELOG.md", "LICENSE.txt"].freeze

def update_file_version(file_path, current_version, new_version)
  return unless File.exist?(file_path)

  content = File.read(file_path)

  case file_path
  when /version\.rb$/
    updated = content.gsub(/VERSION = "#{Regexp.escape(current_version)}"/, %(VERSION = "#{new_version}"))
  when "Gemfile.lock"
    updated = content.gsub(/rtlsdr \(#{Regexp.escape(current_version)}\)/, "rtlsdr (#{new_version})")
  when "CHANGELOG.md"
    date = Time.now.strftime("%Y-%m-%d")
    new_entry = "\n## [#{new_version}] - #{date}\n\n### Added\n\n### Changed\n\n### Fixed\n\n"

    updated = if content.include?("## [Unreleased]")
                content.sub(/(## \[Unreleased\].*?\n)/, "\\1#{new_entry}")
              elsif content.include?("# Changelog")
                content.sub(/(# Changelog\s*\n)/, "\\1#{new_entry}")
              else
                "# Changelog#{new_entry}#{content}"
              end
  end

  File.write(file_path, updated) if updated
end

def current_version
  require_relative "lib/rtlsdr/version"
  RTLSDR::VERSION
end

RDoc::Task.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = "doc"
  rdoc.title = DOC_TITLE
  rdoc.main = "README.md"
  rdoc.rdoc_files.include(*DOC_FILES.first(1), *DOC_FILES[2..-1])
  rdoc.options << "--line-numbers" << "--all" << "--charset=UTF-8"
  %w[spec examples bin exe].each { |dir| rdoc.options << "--exclude=#{dir}/" }
  rdoc.options << "--template=hanna" if system("gem list hanna -i > /dev/null 2>&1")
end

YARD::Rake::YardocTask.new(:yard) do |yard|
  yard.files = DOC_FILES
  yard.options = [
    "--output-dir", "doc",
    "--readme", "README.md",
    "--title", DOC_TITLE,
    "--markup", "markdown",
    "--markup-provider", "redcarpet",
    "--protected",
    "--no-private",
    "--embed-mixins"
  ]
end

desc "Generate documentation"
task :docs do
  puts "Generating documentation..."

  system("rdoc --verbose lib/")
  system("yard doc")
end

desc "Clean generated documentation"
task :clean_docs do
  rm_rf ["doc", ".yardoc"]
end

namespace :version do
  desc "Show current version"
  task :show do
    puts "Current version: #{current_version}"
  end

  %i[patch minor major].each do |type|
    desc "Bump #{type} version"
    task type do
      bump_version(type)
    end
  end
end

desc "Bump patch version (shortcut)"
task bump: "version:patch"

desc "Release: bump version, update changelog, commit, tag, and push"
task :release do
  puts "Make sure you have committed all your changes before running this task."
  print "Do you want to continue? (yes/no): "

  if $stdin.gets.chomp.downcase == "yes"
    old_version = current_version
    Rake::Task["version:patch"].invoke

    version_content = File.read("lib/rtlsdr/version.rb")
    new_version = version_content.match(/VERSION = "([^"]+)"/)[1]

    puts "Hit enter when you've updated the CHANGELOG"
    $stdin.gets

    system("git add -A && git commit -m 'Bump version to #{new_version}'")
    system("git tag v#{new_version}")
    system("git push && git push --tags")

    puts "Release process completed successfully!"
    Rake::Task["release"].invoke
  else
    puts "Release process aborted."
  end
end

def bump_version(type)
  version_file = "lib/rtlsdr/version.rb"
  content = File.read(version_file)
  current_ver = content.match(/VERSION = "([^"]+)"/)[1]

  major, minor, patch = current_ver.split(".").map(&:to_i)

  case type
  when :patch then patch += 1
  when :minor then minor += 1; patch = 0
  when :major then major += 1; minor = 0; patch = 0
  end

  new_version = "#{major}.#{minor}.#{patch}"

  [version_file, "Gemfile.lock", "CHANGELOG.md"].each do |file|
    update_file_version(file, current_ver, new_version)
  end

  puts "Version bumped from #{current_ver} to #{new_version}"
  puts "Updated Gemfile.lock" if File.exist?("Gemfile.lock")
  puts "Updated CHANGELOG.md with new version entry" if File.exist?("CHANGELOG.md")
end

task default: %i[spec rubocop docs]
