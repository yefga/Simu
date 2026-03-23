# frozen_string_literal: true

require "json"

module Simu
  class IOS < Thor
    desc "list", "List available iOS simulators"
    def list
      Simu::Setup.ensure_ios_tools!
      
      output = `xcrun simctl list devices available -j`
      data = JSON.parse(output)
      
      rows = []
      data["devices"].each do |runtime, devices|
        os_version = runtime.split(".").last.gsub("-", ".")
        devices.each do |device|
          rows << [device["name"], os_version, device["state"], device["udid"]]
        end
      end
      
      Simu::UI.render_table(
        title: "Available iOS Simulators",
        headings: ["Name", "OS Version", "State", "UDID"],
        rows: rows
      )
    end

    map "run" => :run_device

    desc "run [DEVICE_NAME] [OS_VERSION]", "Run a specific iOS simulator"
    def run_device(device_name = nil, os_version = nil)
      Simu::Setup.ensure_ios_tools!

      output = `xcrun simctl list devices available -j`
      data = JSON.parse(output)
      
      devices = []
      data["devices"].each do |runtime, runtime_devices|
        version = runtime.split(".").last.gsub("-", ".")
        runtime_devices.each do |device|
          devices << {
            name: device["name"],
            version: version,
            udid: device["udid"],
            state: device["state"]
          }
        end
      end

      if device_name.nil?
        choices = devices.map do |d|
          { name: "#{d[:name]} (#{d[:version]}) - #{d[:state]}", value: d }
        end
        
        Simu::UI.error("No available iOS simulators found.") if choices.empty?

        selected = Simu::UI.prompt.select("Choose an iOS simulator to run:", choices, per_page: 15)
        boot_simulator(selected[:udid])
      else
        target = devices.find do |d| 
          d[:name].downcase.gsub(/\s+/, "") == device_name.downcase.gsub(/\s+/, "") && 
          (os_version.nil? || d[:version].downcase.gsub(/[^0-9]/, "") == os_version.downcase.gsub(/[^0-9]/, ""))
        end
        
        if target
          boot_simulator(target[:udid])
        else
          Simu::UI.error("Could not find iOS simulator matching '#{device_name}' '#{os_version}'")
        end
      end
    end

    private

    def boot_simulator(udid)
      # Simulators might already be booted or Booted but not visually opened
      Simu::UI.info("Booting simulator (UDID: #{udid})...")
      system("xcrun simctl boot #{udid}") # Ignore error if already booted
      Simu::UI.info("Opening Simulator app...")
      system("open -a Simulator")
    end
  end
end
