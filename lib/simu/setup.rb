# frozen_string_literal: true

require "mkmf"

module Simu
  class Setup
    class << self
      def ensure_ios_tools!
        unless find_executable("xcrun")
          Simu::UI.error("xcrun not found. Please install Xcode Command Line Tools by running 'xcode-select --install'")
        end
      end

      def ensure_android_tools!
        unless find_executable("emulator")
          prompt_android_install
        end
      end

      private

      def prompt_android_install
        Simu::UI.info("Android emulator not found in PATH.")
        if Simu::UI.prompt.yes?("Would you like to see instructions on how to install Android Studio via Homebrew?")
          Simu::UI.success("Run: brew install --cask android-studio")
          Simu::UI.info("After installation, ensure you add the emulator to your PATH (e.g., export PATH=\"$HOME/Library/Android/sdk/emulator:$PATH\")")
        end
        exit 1
      end
    end
  end
end
