# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "hotdog/version"

Gem::Specification.new do |spec|
  spec.name          = "hotdog"
  spec.version       = Hotdog::VERSION
  spec.authors       = ["Yamashita Yuu"]
  spec.email         = ["peek824545201@gmail.com"]
  spec.summary       = %q{Yet another command-line tool for Datadog}
  spec.description   = %q{Yet another command-line tool for Datadog}
  spec.homepage      = "https://github.com/yyuu/hotdog"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.3.0"
  spec.add_development_dependency "rubocop", "~> 0.35.1"

  spec.add_dependency "dogapi", ">= 1.13.0"
  spec.add_dependency "multi_json", "~> 1.11.2"
  spec.add_dependency "oj", "~> 2.12.14"
  spec.add_dependency "parallel", "~> 1.6.1"
  spec.add_dependency "parslet", "~> 1.6.2"
  spec.add_dependency "sqlite3", "~> 1.3.10"
end
