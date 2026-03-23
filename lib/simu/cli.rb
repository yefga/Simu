# frozen_string_literal: true

require "thor"

module Simu
  class CLI < Thor
    desc "version", "Display simu version"
    def version
      puts Simu::VERSION
    end

    desc "ios SUBCOMMAND", "Manage iOS simulators"
    subcommand "ios", Simu::IOS

    desc "android SUBCOMMAND", "Manage Android emulators"
    subcommand "android", Simu::Android
  end
end
