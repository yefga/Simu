# frozen_string_literal: true

require 'json'

module Simu
  class Apple < Thor
    remove_command(:tree) if respond_to?(:remove_command)

    def self.exit_on_failure?
      true
    end

    map %w[--help -h] => :help

    no_commands do
      def get_all_devices
        Simu::Setup.ensure_apple_tools!
        require 'json'
        
        devices = []

        sim_sizes = {}
        begin
          json_out = `xcrun simctl list devices -j 2>/dev/null`
          data = JSON.parse(json_out)
          data['devices'].each do |_os, sims|
            sims.each do |sim|
              sim_sizes[sim['udid']] = sim['dataPathSize'] if sim['dataPathSize']
            end
          end
        rescue StandardError
          # ignore parse errors
        end

        output = `xcrun xctrace list devices 2>&1`
        lines = output.split("\n")
        
        parsing_devices = false
        
        lines.each do |line|
          if line.start_with?('== Devices ==')
            parsing_devices = true
            next
          elsif line.start_with?('== Simulators ==')
            parsing_devices = false
            next
          end

          next if line.strip.empty? || line.include?('xctrace')

          match = line.match(/^(.*?)\s+(?:\((.*?)\)\s+)?\(([\w-]+)\)$/)
          next unless match

          name = match[1].strip
          os_version = match[2]&.strip || 'Unknown'
          device_id = match[3].strip

          tag = 'Simulator'
          if parsing_devices
            tag = name.include?('Offline') ? 'Physical (Offline)' : 'Physical'
          end

          size = 'N/A'
          if tag == 'Simulator' && sim_sizes[device_id]
            size = Simu::Utils.format_size(sim_sizes[device_id])
          end

          devices << { name: name, os_version: os_version, tag: tag, id: device_id, size: size }
        end
        
        devices
      end
    end

    desc 'list', 'List available Apple devices and simulators'
    def list
      devices = get_all_devices
      rows = devices.map { |d| [d[:name], d[:os_version], d[:tag], d[:id], d[:size]] }

      if rows.empty?
        Simu::UI.info('No Apple devices or simulators found.')
      else
        Simu::UI.render_table(title: 'Available Apple Devices', headings: ['Name', 'OS Version', 'Type', 'Identifier', 'Size'], rows: rows)
      end
    end

    desc 'doctor', 'Check Apple simulator dependencies'
    def doctor
      Simu::UI.info('Apple Doctor Summary:')

      if system('which xcrun > /dev/null 2>&1')
        Simu::UI.doctor_success('Xcode Command Line Tools (xcrun) is installed')
      else
        Simu::UI.doctor_error('Xcode Command Line Tools is missing. Fix: xcode-select --install')
      end

      if system('xcode-select -p > /dev/null 2>&1')
        Simu::UI.doctor_success('Xcode is installed and path is configured')
      else
        Simu::UI.doctor_error('Xcode is not installed or path is not set. Download from Mac App Store.')
      end
    end

    map 'run' => :run_device

    desc 'run [DEVICE_NAME] [OS_VERSION]', 'Run a specific Apple simulator'
    def run_device(device_name = nil, os_version = nil)
      Simu::Setup.ensure_apple_tools!

      spinner = TTY::Spinner.new("[:spinner] Fetching Apple devices...", format: :classic)
      spinner.auto_spin
      devices = get_all_devices
      spinner.success "Done!\n"

      if device_name.nil?
        choices = devices.map do |d|
          { name: "#{d[:name]} (#{d[:os_version]}) - #{d[:tag]}", value: d }
        end

        Simu::UI.error('No available Apple devices or simulators found.') if choices.empty?

        selected = Simu::UI.prompt.select('Choose an Apple device/simulator to run:', choices, per_page: 15)

        handle_selection(selected)
      else
        target = devices.find do |d|
          # Match precisely by UDID
          next true if d[:id].downcase == device_name.downcase

          # Fuzzy match name
          clean_name = device_name.downcase.gsub(/[^a-z0-9]/, '')
          actual_name_clean = d[:name].downcase.gsub(/[^a-z0-9]/, '')
          name_match = actual_name_clean.include?(clean_name)

          # Fuzzy match OS version
          if os_version
            clean_os = os_version.downcase.gsub(/[^0-9]/, '')
            actual_os_clean = d[:os_version].downcase.gsub(/[^0-9]/, '')
            version_match = actual_os_clean.include?(clean_os)
          else
            version_match = true
          end

          name_match && version_match
        end

        if target
          handle_selection(target)
        else
          Simu::UI.error("Could not find Apple device matching '#{device_name}' #{os_version}")
        end
      end
    end

    map 'launch' => :launch_path

    desc 'launch [PATH]', 'Build and run an iOS project or .app on a specific simulator'
    def launch_path(path = '.')
      path = File.expand_path(path)
      unless File.exist?(path)
        Simu::UI.error("Path not found: #{path}")
        return
      end

      devices = get_all_devices
      choices = devices.map { |d| { name: "#{d[:name]} (#{d[:os_version]}) - #{d[:tag]}", value: d } }
      Simu::UI.error('No available Apple devices or simulators found.') if choices.empty?

      selected_device = Simu::UI.prompt.select('Choose an Apple device/simulator to launch on:', choices, per_page: 15)
      
      udid = selected_device[:id]

      if selected_device[:tag] == 'Simulator'
        system("xcrun simctl boot #{udid} 2>/dev/null")
        system("open -a Simulator")
      end

      if path.end_with?('.app')
        launch_app(path, udid)
      else
        build_and_launch_ios_project(path, udid)
      end
    end

    private

    def launch_app(app_path, udid)
      spinner = TTY::Spinner.new("[:spinner] Installing app to simulator...", format: :classic)
      spinner.auto_spin
      system("xcrun simctl install #{udid} '#{app_path}'")
      spinner.success "Installed!"

      bundle_id = `osascript -e 'id of app "#{app_path}"' 2>/dev/null`.strip
      if bundle_id.empty?
        plist_path = File.join(app_path, 'Info.plist')
        bundle_id = `plutil -extract CFBundleIdentifier raw "#{plist_path}" 2>/dev/null`.strip if File.exist?(plist_path)
      end

      if bundle_id && !bundle_id.empty?
        Simu::UI.info("Launching #{bundle_id}...")
        system("xcrun simctl launch #{udid} #{bundle_id}")
        Simu::UI.success("Launch complete!")
      else
        Simu::UI.error("Could not determine Bundle ID for #{app_path}")
      end
    end

    def build_and_launch_ios_project(project_path, udid)
      require 'tmpdir'
      require 'json'
      
      derived_data = Dir.mktmpdir("simu-derivedData")
      
      spinner = TTY::Spinner.new("[:spinner] Building iOS project (this may take a while)...", format: :classic)
      spinner.auto_spin

      workspace = Dir.glob(File.join(project_path, '*.xcworkspace')).first
      project = Dir.glob(File.join(project_path, '*.xcodeproj')).first
      
      unless workspace || project
        spinner.error "Failed!"
        Simu::UI.error("No .xcworkspace or .xcodeproj found in #{project_path}")
        return
      end

      schemes_output = workspace ? `xcodebuild -workspace '#{workspace}' -list -json 2>/dev/null` : `xcodebuild -project '#{project}' -list -json 2>/dev/null`
      scheme = nil
      begin
        parsed = JSON.parse(schemes_output)
        scheme = parsed['workspace']['schemes'].first if parsed['workspace']
        scheme = parsed['project']['schemes'].first if parsed['project']
      rescue StandardError => e
        Simu::UI.error("Could not parse scheme: #{e.message}")
        nil
      end
      
      unless scheme
        spinner.error "Failed!"
        Simu::UI.error("Could not detect any Xcode schemes in #{project_path}.")
        return
      end

      cmd = if workspace
              "xcodebuild -workspace '#{workspace}' -scheme '#{scheme}' -destination 'id=#{udid}' -derivedDataPath '#{derived_data}' build >/dev/null 2>&1"
            else
              "xcodebuild -project '#{project}' -scheme '#{scheme}' -destination 'id=#{udid}' -derivedDataPath '#{derived_data}' build >/dev/null 2>&1"
            end

      if system(cmd)
        spinner.success "Built successfully!"
        
        # In DerivedData, Simulator builds go to Build/Products/*-iphonesimulator/*.app
        app_path = Dir.glob(File.join(derived_data, 'Build', 'Products', '*-iphonesimulator', '*.app')).first
        if app_path
          launch_app(app_path, udid)
        else
          Simu::UI.error("Build succeeded but could not locate .app in DerivedData.")
        end
      else
        spinner.error "Build Failed!"
        Simu::UI.error("xcodebuild returned a non-zero exit code. Run manually to see logs:\n#{cmd.gsub(' >/dev/null 2>&1', '')}")
      end
    ensure
      FileUtils.rm_rf(derived_data) if derived_data && Dir.exist?(derived_data)
    end

    def handle_selection(device)
      if device[:tag] == 'Simulator'
        boot_simulator(device[:id])
      elsif device[:tag] == 'Physical (Offline)'
        Simu::UI.error("Device '#{device[:name]}' is currently offline.")
      else
        Simu::UI.info("Device '#{device[:name]}' is a physical device and is already running.")
      end
    end

    def boot_simulator(udid)
      # Simulators might already be booted or Booted but not visually opened
      Simu::UI.info("Booting simulator (UDID: #{udid})...")
      system("xcrun simctl boot #{udid} 2>/dev/null") # Ignore error if already booted
      Simu::UI.info('Opening Simulator app...')
      system('open -a Simulator')
    end
  end
end
