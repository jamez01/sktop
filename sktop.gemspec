# frozen_string_literal: true

require_relative "lib/sktop/version"

Gem::Specification.new do |spec|
  spec.name          = "sktop"
  spec.version       = Sktop::VERSION
  spec.authors       = ["James"]
  spec.email         = ["james@ruby-code.com"]

  spec.summary       = "CLI tool to monitor Sidekiq queues and processes"
  spec.description   = "A terminal-based dashboard for monitoring Sidekiq, similar to the web UI but for the command line"
  spec.homepage      = "https://github.com/jamez01/sktop"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

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

  spec.post_install_message = <<~MSG

    ╔══════════════════════════════════════════════════════════════════╗
    ║                     sktop installed successfully!                ║
    ╠══════════════════════════════════════════════════════════════════╣
    ║  Sidekiq Pro/Enterprise Support (Optional)                       ║
    ║  ──────────────────────────────────────────                      ║
    ║  To enable Batches and Periodic Jobs views, install the          ║
    ║  commercial Sidekiq gems:                                        ║
    ║                                                                  ║
    ║  # Configure credentials (one-time setup)                        ║
    ║  export BUNDLE_ENTERPRISE__CONTRIBSYS__COM=YOUR_LICENSE_KEY      ║
    ║                                                                  ║
    ║  # Install Pro (for Batches)                                     ║
    ║  gem install sidekiq-pro \\                                       ║
    ║    --source https://enterprise.contribsys.com/                   ║
    ║                                                                  ║
    ║  # Install Enterprise (for Batches + Periodic Jobs)              ║
    ║  gem install sidekiq-ent \\                                       ║
    ║    --source https://enterprise.contribsys.com/                   ║
    ║                                                                  ║
    ║  More info: https://sidekiq.org                                  ║
    ╚══════════════════════════════════════════════════════════════════╝

  MSG
end
