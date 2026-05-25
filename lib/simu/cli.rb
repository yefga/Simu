# frozen_string_literal: true

require 'thor'

module Simu
  class CLI < Thor
    remove_command(:tree) if respond_to?(:remove_command)

    def self.exit_on_failure?
      true
    end

    map %w[--help -h] => :help

    desc 'list', 'List all available simulators and emulators on this host'
    def list
      spinner = TTY::Spinner.new('[:spinner] Fetching devices across all platforms...', format: :classic)
      spinner.auto_spin

      apple_rows = []
      if Simu::AndroidToolchain.host.os == :macos
        apple = Simu::Apple.new
        apple_devices = apple.get_all_devices
        apple_rows = apple_devices.map { |d| [d[:name], d[:os_version], d[:tag], d[:size]] }
      end

      android = Simu::Android.new
      android_devices = android.get_all_avds
      android_rows = android_devices.map { |a| [a[:name], a[:api], a[:state], a[:size]] }

      spinner.success 'Done!'
      puts

      if Simu::AndroidToolchain.host.os != :macos
        Simu::UI.info('Apple simulators are unavailable on this host; showing Android emulators only.')
      elsif apple_rows.empty?
        Simu::UI.info('No Apple devices or simulators found.')
      else
        headings = ['Name', 'OS Version', 'Type', 'Size']
        Simu::UI.render_table(title: ' Apple Devices', headings: headings, rows: apple_rows)
      end

      puts

      if android_rows.empty?
        Simu::UI.info('No Android emulators found.')
      else
        headings = ['Name', 'API Version', 'State', 'Size']
        Simu::UI.render_table(title: '🤖 Android Emulators', headings: headings, rows: android_rows)
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
