# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "sktop"
  spec.version       = "0.1.0"
  spec.authors       = ["James"]
  spec.email         = ["james@example.com"]

  spec.summary       = "CLI tool to monitor Sidekiq queues and processes"
  spec.description   = "A terminal-based dashboard for monitoring Sidekiq, similar to the web UI but for the command line"
  spec.homepage      = "https://github.com/james/sktop"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.files         = Dir["lib/**/*", "bin/*", "README.md", "LICENSE"]
  spec.bindir        = "bin"
  spec.executables   = ["sktop"]
  spec.require_paths = ["lib"]

  spec.add_dependency "sidekiq", ">= 6.0"
  spec.add_dependency "redis", ">= 4.0"
  spec.add_dependency "terminal-table", "~> 3.0"
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "tty-cursor", "~> 0.7"
  spec.add_dependency "tty-screen", "~> 0.8"
end
