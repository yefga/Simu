# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'simu'
  spec.version       = '0.1.0'
  spec.authors       = ['yefga']
  spec.email         = ['yefga@users.noreply.github.com']
  spec.summary       = 'CLI tool to manage iOS simulators and Android emulators on macOS.'
  spec.description   = 'simu provides an easy way to list and run iOS and Android simulators using a modern terminal UI.'
  spec.homepage      = 'https://github.com/yefga/Simu'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.files         = Dir['lib/**/*', 'bin/*', 'LICENSE', 'README.md'].reject { |f| File.directory?(f) }
  spec.bindir        = 'bin'
  spec.executables   = ['simu']
  spec.require_paths = ['lib']

  spec.add_dependency 'pastel', '~> 0.8'
  spec.add_dependency 'terminal-table', '~> 3.0'
  spec.add_dependency 'thor', '~> 1.2'
  spec.add_dependency 'tty-prompt', '~> 0.23'
end
