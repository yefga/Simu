# frozen_string_literal: true

require 'open3'
require 'timeout'

module Simu
  # Thor command group for Android emulator setup and execution.
  class Android < Thor
    remove_command(:tree) if respond_to?(:remove_command)
    stop_on_unknown_option! :exec_command

    def self.exit_on_failure?
      true
    end

    map %w[--help -h] => :help

    desc 'doctor', 'Check Android emulator dependencies and setup readiness'
    def doctor
      Simu::UI.info('Android Doctor Summary:')
      host = Simu::AndroidToolchain.host

      unless Simu::AndroidToolchain.supported_host?(host)
        Simu::UI.doctor_error(Simu::AndroidToolchain.unsupported_host_message(host))
        return
      end
      Simu::UI.doctor_success("Supported host detected: #{host.label}")

      toolchain = Simu::AndroidToolchain.external
      if toolchain
        Simu::UI.doctor_success("Using existing Android SDK: #{toolchain.sdk_root || 'tools available in PATH'}")
      elsif Simu::AndroidToolchain.managed.usable?
        toolchain = Simu::AndroidToolchain.managed
        Simu::UI.doctor_success("Using Simu-managed Android SDK: #{toolchain.sdk_root}")
      else
        Simu::UI.doctor_error('No runnable Android emulator and ADB installation was found.')
        Simu::UI.info('Run `simu android setup` to install a private emulator environment without Android Studio.')
        report_archive_tools
        return
      end

      report_binary('Android Emulator', toolchain.emulator_bin)
      report_binary('ADB', toolchain.adb_bin)
      inspector = toolchain.apk_inspector_bin
      if inspector
        Simu::UI.doctor_success("APK inspection tool is available at #{inspector}")
      else
        Simu::UI.doctor_error('APK inspection tool (aapt) is missing; APK launch cannot determine its package name.')
      end

      avds = toolchain.avd_names
      if avds.empty?
        Simu::UI.doctor_error('No Android virtual devices are configured. Run `simu android setup` to create one.')
      else
        Simu::UI.doctor_success("Configured Android virtual devices: #{avds.join(', ')}")
      end

      accelerated, detail = toolchain.acceleration_status
      if accelerated
        Simu::UI.doctor_success("Emulator acceleration is available: #{detail}")
      else
        Simu::UI.doctor_error("Emulator acceleration could not be verified: #{detail}")
      end

      managed_java = Simu::AndroidToolchain.managed.java_bin
      if managed_java
        Simu::UI.doctor_success("Private setup Java runtime is available at #{managed_java}")
      else
        Simu::UI.info('Java is not required to boot an existing emulator; setup installs')
        Simu::UI.info('a private runtime when provisioning is needed.')
      end
    end

    desc 'setup', 'Install a private Android emulator environment and create an emulator'
    def setup
      Simu::AndroidInstaller.new.setup!
    end

    no_commands do
      def get_all_avds(toolchain = nil)
        toolchain ||= Simu::Setup.ensure_android_tools!
        names = toolchain.avd_names

        names.map do |name|
          avd_path = File.join(toolchain.avd_home, "#{name}.avd")
          bytes = Simu::Utils.dir_size(avd_path)
          size = bytes.positive? ? Simu::Utils.format_size(bytes) : 'N/A'
          api = avd_api(toolchain.avd_home, name)

          { name: name, api: api, state: 'Ready', size: size }
        end
      end
    end

    desc 'list', 'List available Android emulators'
    def list
      avds = get_all_avds
      rows = avds.map { |avd| [avd[:name], avd[:api], avd[:state], avd[:size]] }

      if rows.empty?
        Simu::UI.info('No Android emulators found. Run `simu android setup` to create one.')
      else
        headings = ['Name', 'API Version', 'State', 'Size']
        Simu::UI.render_table(title: 'Available Android Emulators', headings: headings, rows: rows)
      end
    end

    map 'run' => :run_device

    desc 'run [AVD_NAME]', 'Run a specific Android emulator'
    def run_device(avd_name = nil)
      toolchain = Simu::Setup.ensure_android_tools!
      spinner = TTY::Spinner.new('[:spinner] Fetching Android emulators...', format: :classic)
      spinner.auto_spin
      avds = get_all_avds(toolchain)
      spinner.success "Done!\n"

      Simu::UI.error('No available Android emulators found. Run `simu android setup` to create one.') if avds.empty?

      if avd_name.nil?
        choices = avds.map { |avd| { name: "#{avd[:name]} (API #{avd[:api]})", value: avd[:name] } }
        selected = Simu::UI.prompt.select('Choose an Android emulator to run:', choices, per_page: 15)
        boot_emulator(toolchain, selected)
      else
        target = avds.find { |avd| normalized(avd[:name]) == normalized(avd_name) }

        if target
          boot_emulator(toolchain, target[:name])
        else
          Simu::UI.error("Could not find Android emulator matching '#{avd_name}'")
        end
      end
    end

    map 'launch' => :launch_path

    desc 'launch [PATH]', 'Build and run an Android project or install an APK on an emulator'
    def launch_path(path = '.')
      path = File.expand_path(path)
      unless File.exist?(path)
        Simu::UI.error("Path not found: #{path}")
        return
      end

      toolchain = Simu::Setup.ensure_android_tools!
      avds = get_all_avds(toolchain)
      choices = avds.map { |avd| { name: "#{avd[:name]} (API #{avd[:api]})", value: avd[:name] } }
      Simu::UI.error('No available Android emulators found. Run `simu android setup` to create one.') if choices.empty?

      selected_avd = Simu::UI.prompt.select('Choose an Android emulator to launch on:', choices, per_page: 15)
      boot_emulator(toolchain, selected_avd)
      wait_for_emulator_boot(toolchain)

      if path.downcase.end_with?('.apk')
        launch_apk(toolchain, path)
      else
        build_and_launch_android_project(toolchain, path)
      end
    end

    map 'exec' => :exec_command

    desc 'exec -- COMMAND...', 'Run a framework command with the Simu Android SDK environment'
    def exec_command(*command)
      command.shift if command.first == '--'
      Simu::UI.error('Provide a command after `simu android exec --`.') if command.empty?

      toolchain = Simu::Setup.ensure_android_tools!
      success = system(toolchain.environment, *command)
      exit 1 unless success
    end

    private

    def report_archive_tools
      %w[tar unzip].each do |command|
        path = Simu::AndroidToolchain.find_in_path(command)
        if path
          Simu::UI.doctor_success("Required archive tool is available: #{path}")
        else
          Simu::UI.doctor_error("Required archive tool is missing: #{command}")
        end
      end
    end

    def report_binary(name, path)
      if File.executable?(path)
        Simu::UI.doctor_success("#{name} is available at #{path}")
      else
        Simu::UI.doctor_error("#{name} is missing at #{path}")
      end
    end

    def normalized(name)
      name.downcase.gsub(/\s+/, '')
    end

    def avd_api(avd_home, name)
      ini_path = File.join(avd_home, "#{name}.ini")
      config_path = File.join(avd_home, "#{name}.avd", 'config.ini')
      [ini_path, config_path].each do |path|
        next unless File.file?(path)

        match = File.read(path).match(/android-(\d+)/)
        return match[1] if match
      end
      'Unknown'
    end

    def wait_for_emulator_boot(toolchain)
      spinner = TTY::Spinner.new('[:spinner] Waiting for Android emulator to finish booting...', format: :classic)
      spinner.auto_spin

      Timeout.timeout(180) do
        unless system(toolchain.environment, toolchain.adb_bin, 'wait-for-device', out: File::NULL, err: File::NULL)
          spinner.error 'ADB could not connect to the emulator.'
          Simu::UI.error('ADB could not connect to the Android emulator.')
        end

        loop do
          output, _error, _status = Open3.capture3(
            toolchain.environment,
            toolchain.adb_bin,
            'shell',
            'getprop',
            'init.svc.bootanim'
          )
          break if output.strip == 'stopped'

          sleep 1
        end
      end

      spinner.success 'Ready!'
    rescue Timeout::Error
      spinner.error 'Timed out waiting for Android emulator boot.'
      Simu::UI.error('The Android emulator did not finish booting within 180 seconds.')
    end

    def launch_apk(toolchain, apk_path)
      spinner = TTY::Spinner.new('[:spinner] Installing APK...', format: :classic)
      spinner.auto_spin
      success = system(toolchain.environment, toolchain.adb_bin, 'install', '-r', '-t', apk_path,
                       out: File::NULL, err: File::NULL)
      unless success
        spinner.error 'Install failed!'
        return
      end
      spinner.success 'Installed!'

      inspector = toolchain.apk_inspector_bin
      unless inspector
        Simu::UI.error('APK inspection tool is unavailable. Run `simu android setup` ' \
                       'to install managed build tools.')
      end

      output, _error, _status = Open3.capture3(toolchain.environment, inspector, 'dump', 'badging', apk_path)
      match = output.match(/package:\s+name='([\w.]+)'/)
      if match
        package = match[1]
        Simu::UI.info("Launching #{package}...")
        system(toolchain.environment, toolchain.adb_bin, 'shell', 'monkey', '-p', package,
               '-c', 'android.intent.category.LAUNCHER', '1', out: File::NULL, err: File::NULL)
        Simu::UI.success('Launch complete!')
      else
        Simu::UI.error('Could not extract package name from APK.')
      end
    end

    def build_and_launch_android_project(toolchain, project_path)
      gradlew = File.join(project_path, 'gradlew')
      unless File.executable?(gradlew)
        Simu::UI.error("No executable gradlew wrapper found in #{project_path}")
        return
      end

      spinner = TTY::Spinner.new('[:spinner] Building Android project via Gradle...', format: :classic)
      spinner.auto_spin
      success = system(toolchain.environment, gradlew, 'assembleDebug', chdir: project_path,
                       out: File::NULL, err: File::NULL)

      unless success
        spinner.error 'Build Failed!'
        Simu::UI.error('The project build failed. Project-specific Java, SDK, or NDK ' \
                       'dependencies are not installed by Simu.')
        return
      end

      spinner.success 'Built successfully!'
      apk = Dir.glob(File.join(project_path, 'app', 'build', 'outputs', 'apk', 'debug', '*.apk')).first ||
            Dir.glob(File.join(project_path, '**', 'build', 'outputs', 'apk', '**', '*.apk')).first
      if apk
        launch_apk(toolchain, apk)
      else
        Simu::UI.error('Could not find generated APK in build/outputs.')
      end
    end

    def boot_emulator(toolchain, avd_name)
      Simu::UI.info("Booting Android emulator: #{avd_name}...")
      pid = spawn(toolchain.environment, toolchain.emulator_bin, '-avd', avd_name,
                  out: File::NULL, err: File::NULL)
      Process.detach(pid)
      Simu::UI.success("Emulator #{avd_name} is starting in the background!")
    rescue SystemCallError => e
      Simu::UI.error("Could not start Android emulator: #{e.message}")
    end
  end
end
