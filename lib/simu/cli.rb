# frozen_string_literal: true

require 'thor'

module Simu
  class CLI < Thor
    map %w[--help -h] => :help

    desc 'list', 'List all available simulators and emulators installed on this mac'
    def list
      Simu::UI.info('Fetching devices across all platforms...')
      puts ""

      apple = Simu::Apple.new
      apple_devices = apple.get_all_devices
      apple_rows = apple_devices.map { |d| [d[:name], d[:tag], d[:size]] }
      
      if apple_rows.empty?
        Simu::UI.info('No Apple devices or simulators found.')
      else
        Simu::UI.render_table(title: ' Apple Devices', headings: %w[Name Type Size], rows: apple_rows)
      end
      
      puts ""
      
      android = Simu::Android.new
      android_devices = android.get_all_avds
      android_rows = android_devices.map { |a| [a[:name], a[:state], a[:size]] }
      
      if android_rows.empty?
        Simu::UI.info('No Android emulators found.')
      else
        Simu::UI.render_table(title: '🤖 Android Emulators', headings: %w[Name State Size], rows: android_rows)
      end
    end

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
