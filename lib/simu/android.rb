# frozen_string_literal: true

module Simu
  class Android < Thor
    desc "list", "List available Android emulators"
    def list
      Simu::Setup.ensure_android_tools!
      
      # emulator -list-avds returns a highly simple list of names
      output = `emulator -list-avds`
      avds = output.split("\n").map(&:chomp).reject(&:empty?)
      
      rows = avds.map { |avd| [avd, "Ready"] }
      
      Simu::UI.render_table(
        title: "Available Android Emulators",
        headings: ["Name", "State"],
        rows: rows
      )
    end

    map "run" => :run_device

    desc "run [AVD_NAME]", "Run a specific Android emulator"
    def run_device(avd_name = nil)
      Simu::Setup.ensure_android_tools!

      output = `emulator -list-avds`
      avds = output.split("\n").map(&:chomp).reject(&:empty?)

      if avd_name.nil?
        choices = avds.map { |avd| { name: avd, value: avd } }
        Simu::UI.error("No available Android emulators found.") if choices.empty?

        selected = Simu::UI.prompt.select("Choose an Android emulator to run:", choices, per_page: 15)
        boot_emulator(selected)
      else
        target = avds.find { |a| a.downcase.gsub(/\s+/, "") == avd_name.downcase.gsub(/\s+/, "") }
        
        if target
          boot_emulator(target)
        else
          Simu::UI.error("Could not find Android emulator matching '#{avd_name}'")
        end
      end
    end

    private

    def boot_emulator(avd_name)
      Simu::UI.info("Booting Android emulator: #{avd_name}...")
      
      # Run emulator in the background, redirecting output so the script doesn't hang
      pid = spawn("emulator -avd #{avd_name}", [:out, :err] => "/dev/null")
      Process.detach(pid)
      
      Simu::UI.success("Emulator #{avd_name} is starting in the background!")
    end
  end
end
