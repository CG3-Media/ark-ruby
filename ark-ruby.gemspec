# frozen_string_literal: true

require_relative "lib/ark/version"

Gem::Specification.new do |spec|
  spec.name          = "ark-ruby"
  spec.version       = Ark::VERSION
  spec.authors       = ["Ark"]
  spec.email         = ["hello@example.com"]

  spec.summary       = "Ruby client for Ark error tracking"
  spec.description   = "Automatically capture and report errors from your Ruby/Rails apps to Ark"
  spec.homepage      = "https://github.com/CG3-Media/ark-ruby"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.files         = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "rack", ">= 2.0"
end
