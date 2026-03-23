# frozen_string_literal: true

require 'json'

module Simu
  class Apple < Thor
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

          match = line.match(/^(.*?)\s+\((.*?)\)\s+\((.*?)\)/)
          next unless match

          name = match[1].strip
          device_id = match[3].strip

          tag = 'Simulator'
          if parsing_devices
            tag = name.include?('Offline') ? 'Physical (Offline)' : 'Physical'
          end

          size = 'N/A'
          if tag == 'Simulator' && sim_sizes[device_id]
            size = Simu::Utils.format_size(sim_sizes[device_id])
          end

          devices << { name: name, tag: tag, id: device_id, size: size }
        end
        
        devices
      end
    end

    desc 'list', 'List available Apple devices and simulators'
    def list
      devices = get_all_devices
      rows = devices.map { |d| [d[:name], d[:tag], d[:id], d[:size]] }

      if rows.empty?
        Simu::UI.info('No Apple devices or simulators found.')
      else
        Simu::UI.render_table(title: 'Available Apple Devices', headings: %w[Name Type Identifier Size], rows: rows)
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

      devices = fetch_apple_devices

      if device_name.nil?
        choices = devices.map do |d|
          { name: "#{d[:name]} (#{d[:os_version] || 'N/A'}) - #{d[:type]}", value: d }
        end

        Simu::UI.error('No available Apple devices or simulators found.') if choices.empty?

        selected = Simu::UI.prompt.select('Choose an Apple device/simulator to run:', choices, per_page: 15)

        handle_selection(selected)
      else
        target = devices.find do |d|
          name_match = d[:name].downcase.gsub(/\s+/, '') == device_name.downcase.gsub(/\s+/, '')
          version_match = os_version.nil? || (d[:os_version] && d[:os_version].downcase.gsub(/[^0-9]/,
                                                                                             '') == os_version.downcase.gsub(
                                                                                               /[^0-9]/, ''
                                                                                             ))
          name_match && version_match
        end

        if target
          handle_selection(target)
        else
          Simu::UI.error("Could not find Apple device matching '#{device_name}' '#{os_version}'")
        end
      end
    end

    private

    def fetch_apple_devices
      output = `xcrun xctrace list devices 2>/dev/null`
      devices = []
      current_section = nil

      output.each_line do |line|
        line.strip!
        next if line.empty?

        if line.start_with?('==')
          current_section = line.gsub('==', '').strip
          next
        end

        # Parse Device Line
        # Example 1: Yefga’s MacBook Pro (9314A7DA-BEDD-5399-9EE3-CF2AD26CFCEC)
        # Example 2: Yefga’s Apple Watch (26.0) (00008310-0005535121FBA01E)
        # Example 3: SE 3 - 16.0 Simulator (16.0) (0847094C-8E21-4F73-B245-00674FC49DB6)

        # Regex to match: Name (optional OS) (UDID)
        # UDID is always at the end in parentheses.
        next unless line =~ /^(.*?)\s+(?:\((.*?)\)\s+)?\(([\w-]+)\)$/

        name = ::Regexp.last_match(1).strip
        os = ::Regexp.last_match(2)
        udid = ::Regexp.last_match(3)

        type = if current_section == 'Simulators'
                 'Simulator'
               elsif current_section == 'Devices Offline'
                 'Physical (Offline)'
               else
                 'Physical'
               end

        devices << {
          name: name,
          os_version: os,
          udid: udid,
          type: type
        }
      end

      devices
    end

    def handle_selection(device)
      if device[:type] == 'Simulator'
        boot_simulator(device[:udid])
      elsif device[:type] == 'Physical (Offline)'
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
