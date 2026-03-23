# frozen_string_literal: true

require 'json'

module Simu
  class Apple < Thor
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

    private

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
