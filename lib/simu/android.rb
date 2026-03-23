# frozen_string_literal: true

module Simu
  class Android < Thor
    remove_command(:tree) if respond_to?(:remove_command)

    def self.exit_on_failure?
      true
    end

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
          api = 'Unknown'
          if avd_dir
            avd_path = File.join(avd_dir, "#{name}.avd")
            bytes = Simu::Utils.dir_size(avd_path)
            size = Simu::Utils.format_size(bytes) if bytes > 0

            ini_path = File.join(ENV['HOME'], '.android', 'avd', "#{name}.ini")
            if File.exist?(ini_path)
              content = File.read(ini_path)
              match = content.match(/^target=android-(\d+)/)
              api = match[1] if match
            end
          end

          { name: name, api: api, state: 'Ready', size: size }
        end
      end
    end

    desc 'list', 'List available Android emulators'
    def list
      avds = get_all_avds
      rows = avds.map { |a| [a[:name], a[:api], a[:state], a[:size]] }

      if rows.empty?
        Simu::UI.info('No Android emulators found.')
      else
        Simu::UI.render_table(title: 'Available Android Emulators', headings: ['Name', 'API Version', 'State', 'Size'], rows: rows)
      end
    end

    desc 'run [AVD_NAME]', 'Run a specific Android emulator'
    def run_device(avd_name = nil)
      spinner = TTY::Spinner.new("[:spinner] Fetching Android emulators...", format: :classic)
      spinner.auto_spin
      avds = get_all_avds
      spinner.success "Done!\n"

      if avd_name.nil?
        choices = avds.map { |avd| { name: "#{avd[:name]} (API #{avd[:api]})", value: avd[:name] } }
        Simu::UI.error('No available Android emulators found.') if choices.empty?

        selected = Simu::UI.prompt.select('Choose an Android emulator to run:', choices, per_page: 15)
        boot_emulator(selected)
      else
        target = avds.find { |a| a[:name].downcase.gsub(/\s+/, '') == avd_name.downcase.gsub(/\s+/, '') }

        if target
          boot_emulator(target[:name])
        else
          Simu::UI.error("Could not find Android emulator matching '#{avd_name}'")
        end
      end
    end

    map 'launch' => :launch_path

    desc 'launch [PATH]', 'Build and run an Android project or .apk on a specific emulator'
    def launch_path(path = '.')
      path = File.expand_path(path)
      unless File.exist?(path)
        Simu::UI.error("Path not found: #{path}")
        return
      end

      avds = get_all_avds
      choices = avds.map { |avd| { name: "#{avd[:name]} (API #{avd[:api]})", value: avd[:name] } }
      Simu::UI.error('No available Android emulators found.') if choices.empty?

      selected_avd = Simu::UI.prompt.select('Choose an Android emulator to launch on:', choices, per_page: 15)

      boot_emulator(selected_avd)
      wait_for_emulator_boot

      if path.end_with?('.apk')
        launch_apk(path)
      else
        build_and_launch_android_project(path)
      end
    end

    private

    def wait_for_emulator_boot
      spinner = TTY::Spinner.new("[:spinner] Waiting for Android emulator to finish booting...", format: :classic)
      spinner.auto_spin
      
      system("adb wait-for-device")
      
      loop do
        boot_anim = `adb shell getprop init.svc.bootanim 2>/dev/null`.strip
        break if boot_anim == 'stopped'
        sleep 1
      end
      
      spinner.success "Ready!"
    end

    def launch_apk(apk_path)
      spinner = TTY::Spinner.new("[:spinner] Installing APK...", format: :classic)
      spinner.auto_spin
      success = system("adb install -r -t '#{apk_path}' >/dev/null 2>&1")
      unless success
        spinner.error "Install failed!"
        return
      end
      spinner.success "Installed!"

      aapt_out = `aapt dump badging '#{apk_path}' 2>/dev/null | grep package:`
      match = aapt_out.match(/name='([\w.]+)'/)
      if match
        pkg = match[1]
        Simu::UI.info("Launching #{pkg}...")
        system("adb shell monkey -p #{pkg} -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1")
        Simu::UI.success("Launch complete!")
      else
        Simu::UI.error("Could not extract package name from APK.")
      end
    end

    def build_and_launch_android_project(project_path)
      gradlew = File.join(project_path, 'gradlew')
      unless File.exist?(gradlew)
        Simu::UI.error("No gradlew wrapper found in #{project_path}")
        return
      end

      spinner = TTY::Spinner.new("[:spinner] Building Android project via Gradle...", format: :classic)
      spinner.auto_spin

      Dir.chdir(project_path) do
        success = system("./gradlew assembleDebug >/dev/null 2>&1")
        if success
          spinner.success "Built successfully!"
          apk = Dir.glob(File.join("app", "build", "outputs", "apk", "debug", "*.apk")).first || Dir.glob(File.join("**", "build", "outputs", "apk", "**", "*.apk")).first
          if apk
            launch_apk(File.expand_path(apk))
          else
            Simu::UI.error("Could not find generated APK in build/outputs.")
          end
        else
          spinner.error "Build Failed!"
        end
      end
    end

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
