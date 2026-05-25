# frozen_string_literal: true

module Simu
  # Validates tool availability before platform-specific commands run.
  class Setup
    class << self
      def ensure_apple_tools!
        unless Simu::AndroidToolchain.host.os == :macos
          Simu::UI.error('Apple simulators are available only on macOS.')
        end

        return if system('which xcrun > /dev/null 2>&1')

        Simu::UI.error("xcrun not found. Please install Xcode Command Line Tools by running 'xcode-select --install'")
        exit 1
      end

      def ensure_android_tools!
        host = Simu::AndroidToolchain.host
        unless Simu::AndroidToolchain.supported_host?(host)
          Simu::UI.error(Simu::AndroidToolchain.unsupported_host_message(host))
        end

        toolchain = Simu::AndroidToolchain.resolve
        return toolchain if toolchain

        Simu::UI.error('Android tooling is not configured. Run `simu android doctor`, then `simu android setup`.')
      end
    end
  end
end
