# frozen_string_literal: true

require 'thor'

module Simu
  class CLI < Thor
    map %w[--help -h] => :help

    desc 'version', 'Display simu version'
    def version
      puts Simu::VERSION
    end

    desc 'apple SUBCOMMAND', 'Manage Apple simulators and devices'
    subcommand 'apple', Simu::Apple

    desc 'android SUBCOMMAND', 'Manage Android emulators'
    subcommand 'android', Simu::Android
  end
end
