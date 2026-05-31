# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'simu'
  spec.version       = '0.4.0'
  spec.authors       = ['yefga']
  spec.email         = ['yefga@users.noreply.github.com']
  spec.summary       = 'CLI tool to manage Apple simulators and Android emulators.'
  spec.description   = 'simu runs Apple simulators and provisions Android emulators without Android Studio.'
  spec.homepage      = 'https://github.com/yefga/Simu'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.6.0'

  spec.files         = Dir['lib/**/*', 'bin/*', 'docs/**/*', 'LICENSE', 'README.md'].reject { |f| File.directory?(f) }
  spec.bindir        = 'bin'
  spec.executables   = ['simu']
  spec.require_paths = ['lib']

  spec.add_dependency 'pastel', '~> 0.8'
  spec.add_dependency 'terminal-table', '~> 3.0'
  spec.add_dependency 'thor', '~> 1.2'
  spec.add_dependency 'tty-prompt', '~> 0.23'
  spec.add_dependency 'tty-spinner', '~> 0.9'
end
