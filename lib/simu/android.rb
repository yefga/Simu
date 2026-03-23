# frozen_string_literal: true

module Simu
  class Android < Thor
    map %w[--help -h] => :help

    desc 'doctor', 'Check Android emulator dependencies'
    def doctor
      Simu::UI.info('Android Doctor Summary:')

      java_path = `which java 2>/dev/null`.strip
      if !java_path.empty?
        version_out = `java -version 2>&1`.split("\n").first
        version = version_out ? version_out.gsub('"', '') : 'unknown'
        Simu::UI.doctor_success("Java is installed: #{version} at #{java_path}")
      else
        Simu::UI.doctor_error('Java is missing. Install via Homebrew or appropriate package manager.')
      end

      android_home = ENV.fetch('ANDROID_HOME', ENV.fetch('ANDROID_SDK_ROOT', nil))
      if android_home && Dir.exist?(android_home)
        Simu::UI.doctor_success("Android SDK is configured at: #{android_home}")
      else
        Simu::UI.doctor_error('ANDROID_HOME or ANDROID_SDK_ROOT is not set, or directory does not exist.')
      end

      emulator_path = `which emulator 2>/dev/null`.strip
      if !emulator_path.empty?
        Simu::UI.doctor_success("Android Emulator (emulator) is in PATH at #{emulator_path}")
      else
        Simu::UI.doctor_error('Android Emulator is missing from PATH. Add SDK/emulator to your PATH.')
      end

      adb_path = `which adb 2>/dev/null`.strip
      if !adb_path.empty?
        Simu::UI.doctor_success("Android Debug Bridge (adb) is in PATH at #{adb_path}")
      else
        Simu::UI.doctor_error('ADB is missing from PATH. Add SDK/platform-tools to your PATH.')
      end
    end

    map 'run' => :run_device

    no_commands do
      def get_all_avds
        Simu::Setup.ensure_android_tools!

        output = `#{emulator_bin} -list-avds 2>/dev/null`
        names = output.split("\n").map(&:chomp).reject(&:empty?)

        android_home = ENV.fetch('ANDROID_HOME', ENV.fetch('ANDROID_SDK_ROOT', nil))
        avd_dir = android_home ? File.join(ENV['HOME'], '.android', 'avd') : nil

        names.map do |name|
          size = 'N/A'
          if avd_dir
            avd_path = File.join(avd_dir, "#{name}.avd")
            bytes = Simu::Utils.dir_size(avd_path)
            size = Simu::Utils.format_size(bytes) if bytes > 0
          end

          { name: name, state: 'Ready', size: size }
        end
      end
    end

    desc 'list', 'List available Android emulators'
    def list
      avds = get_all_avds
      rows = avds.map { |a| [a[:name], a[:state], a[:size]] }

      if rows.empty?
        Simu::UI.info('No Android emulators found.')
      else
        Simu::UI.render_table(title: 'Available Android Emulators', headings: %w[Name State Size], rows: rows)
      end
    end

    desc 'run [AVD_NAME]', 'Run a specific Android emulator'
    def run_device(avd_name = nil)
      avds = get_all_avds.map { |avd| avd[:name] }

      if avd_name.nil?
        choices = avds.map { |avd| { name: avd, value: avd } }
        Simu::UI.error('No available Android emulators found.') if choices.empty?

        selected = Simu::UI.prompt.select('Choose an Android emulator to run:', choices, per_page: 15)
        boot_emulator(selected)
      else
        target = avds.find { |a| a.downcase.gsub(/\s+/, '') == avd_name.downcase.gsub(/\s+/, '') }

        if target
          boot_emulator(target)
        else
          Simu::UI.error("Could not find Android emulator matching '#{avd_name}'")
        end
      end
    end

    private

    def emulator_bin
      android_home = ENV.fetch('ANDROID_HOME', ENV.fetch('ANDROID_SDK_ROOT', nil))
      if android_home
        sdk_emulator = File.join(android_home, 'emulator', 'emulator')
        return sdk_emulator if File.exist?(sdk_emulator)
      end
      'emulator'
    end

    def boot_emulator(avd_name)
      Simu::UI.info("Booting Android emulator: #{avd_name}...")

      pid = spawn("#{emulator_bin} -avd #{avd_name}", %i[out err] => '/dev/null')
      Process.detach(pid)

      Simu::UI.success("Emulator #{avd_name} is starting in the background!")
    end
  end
end
