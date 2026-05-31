# frozen_string_literal: true

require 'fileutils'

module Simu
  # Exposes the global Android SDK to the user's interactive shell so external
  # toolchains (React Native `npm run android`, Flutter `flutter run`, Gradle) can
  # find ANDROID_HOME, JAVA_HOME, adb, and the emulator. Simu owns nothing here
  # beyond a marker-bounded block in the user's shell profile.
  module AndroidShellEnv
    BEGIN_MARKER = '# >>> simu android >>>'
    END_MARKER = '# <<< simu android <<<'

    module_function

    # Writes the marker-bounded export block into the user's shell profiles.
    # Returns the list of profile paths that were created or changed.
    def apply!(toolchain)
      block = profile_block(toolchain)
      profile_paths.select { |path| write_block!(path, block) }
    end

    def export_lines(toolchain)
      vars, path_entries = toolchain.shell_profile_exports
      lines = vars.map { |key, value| %(export #{key}="#{value}") }
      lines << %(export PATH="#{(path_entries + ['$PATH']).join(File::PATH_SEPARATOR)}")
      lines
    end

    # Plain exports without markers, for `eval "$(simu android env)"` or non-POSIX shells.
    def export_script(toolchain)
      "#{export_lines(toolchain).join("\n")}\n"
    end

    def profile_block(toolchain)
      ([BEGIN_MARKER] + export_lines(toolchain) + [END_MARKER]).join("\n")
    end

    # Writes to the primary profile for the user's actual login shell (creating it
    # if needed) so the config always takes effect, then also updates any other
    # standard profile that already exists so it applies across shells too.
    def profile_paths
      home = Dir.home
      paths = primary_profiles(home)
      %w[.zshrc .bashrc .bash_profile .profile].each do |name|
        candidate = File.join(home, name)
        paths << candidate if File.exist?(candidate)
      end
      paths.uniq
    end

    def primary_profiles(home)
      case File.basename(ENV['SHELL'].to_s)
      when 'bash'
        # macOS Terminal launches login shells (.bash_profile); Linux interactive shells read .bashrc.
        [File.join(home, Simu::AndroidToolchain.host.os == :macos ? '.bash_profile' : '.bashrc')]
      else
        [File.join(home, '.zshrc')]
      end
    end

    def configured?
      profile_paths.any? { |path| File.file?(path) && File.read(path).include?(BEGIN_MARKER) } || env_exposes_sdk?
    end

    def env_exposes_sdk?
      configured_root = ENV['ANDROID_HOME'] || ENV['ANDROID_SDK_ROOT']
      !(configured_root.nil? || configured_root.empty?) && !Simu::AndroidToolchain.find_in_path('adb').nil?
    end

    def write_block!(path, block)
      existing = File.exist?(path) ? File.read(path) : ''
      if existing.include?(BEGIN_MARKER) && existing.include?(END_MARKER)
        replace_block(path, existing, block)
      else
        append_block(path, existing, block)
      end
    end

    def replace_block(path, existing, block)
      updated = existing.sub(/#{Regexp.escape(BEGIN_MARKER)}.*?#{Regexp.escape(END_MARKER)}/m, block)
      return false if updated == existing

      File.write(path, updated)
      true
    end

    def append_block(path, existing, block)
      separator = existing.empty? || existing.end_with?("\n") ? '' : "\n"
      File.write(path, "#{existing}#{separator}\n#{block}\n")
      true
    end
  end
end
