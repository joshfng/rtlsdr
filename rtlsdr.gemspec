# frozen_string_literal: true

require_relative "lib/rtlsdr/version"

Gem::Specification.new do |spec|
  spec.name = "rtlsdr"
  spec.version = RTLSDR::VERSION
  spec.authors = ["joshfng"]
  spec.email = ["me@joshfrye.dev"]

  spec.summary       = "Ruby bindings for librtlsdr"
  spec.description   = "Ruby bindings for librtlsdr - turn RTL2832 based DVB dongles into SDR receivers"
  spec.homepage      = "https://github.com/joshfng/rtlsdr-ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/joshfng/rtlsdr-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/joshfng/rtlsdr-ruby/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/rtlsdr"
  spec.metadata["bug_tracker_uri"] = "https://github.com/joshfng/rtlsdr-ruby/issues"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ffi", "~> 1.15"

  # RDoc configuration
  spec.rdoc_options = ["--main", "README.md", "--line-numbers", "--all"]
  spec.extra_rdoc_files = ["README.md", "CHANGELOG.md", "LICENSE.txt"]
end
