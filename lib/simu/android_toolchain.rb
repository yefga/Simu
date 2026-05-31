# frozen_string_literal: true

require 'open3'
require 'rbconfig'

module Simu
  # Resolves either a user-configured Android SDK or Simu's private SDK paths.
  class AndroidToolchain
    Host = Struct.new(:os, :arch) do
      def label
        "#{os} #{arch}"
      end
    end

    attr_reader :sdk_root, :avd_home, :source

    class << self
      def host
        os = case RbConfig::CONFIG['host_os']
             when /darwin/
               :macos
             when /linux/
               :linux
             else
               :unsupported
             end
        arch = case RbConfig::CONFIG['host_cpu']
               when /arm64|aarch64/
                 :arm64
               when /x86_64|amd64/
                 :x86_64
               else
                 :unsupported
               end

        Host.new(os, arch)
      end

      def supported_host?(candidate = host)
        return true if candidate.os == :macos && %i[arm64 x86_64].include?(candidate.arch)
        return true if candidate.os == :linux && candidate.arch == :x86_64

        false
      end

      def unsupported_host_message(candidate = host)
        if candidate.os == :linux && candidate.arch == :arm64
          'Android Emulator does not officially support Linux ARM hosts. Use macOS arm64 or an x86_64 Linux/macOS host.'
        else
          "Android Emulator setup is unsupported on #{candidate.label}. " \
            'Supported hosts are macOS arm64/x86_64 and Linux x86_64.'
        end
      end

      def simu_home
        ENV.fetch('SIMU_HOME', File.join(Dir.home, '.simu'))
      end

      def managed_sdk_root
        File.join(simu_home, 'android', 'sdk')
      end

      def managed_avd_home
        File.join(simu_home, 'android', 'avd')
      end

      def managed_user_home
        File.join(simu_home, 'android', 'user')
      end

      def managed_runtime_root
        File.join(simu_home, 'android', 'runtime')
      end

      def managed_env_file
        File.join(simu_home, 'android', 'env.sh')
      end

      def managed
        new(sdk_root: managed_sdk_root, avd_home: managed_avd_home, source: :managed)
      end

      def external
        external_candidates.find(&:usable?)
      end

      def resolve
        external || (managed.usable? ? managed : nil)
      end

      def external_candidates
        roots = [
          ENV['ANDROID_HOME'],
          ENV['ANDROID_SDK_ROOT'],
          File.join(Dir.home, 'Library', 'Android', 'sdk'),
          File.join(Dir.home, 'Android', 'Sdk'),
          File.join(Dir.home, 'Android', 'sdk')
        ].compact.uniq.reject { |root| File.expand_path(root) == File.expand_path(managed_sdk_root) }

        candidates = roots.map do |root|
          new(sdk_root: root, avd_home: ENV['ANDROID_AVD_HOME'] || default_avd_home, source: :external)
        end

        emulator = find_in_path('emulator')
        adb = find_in_path('adb')
        if emulator && adb
          candidates << new(
            sdk_root: infer_sdk_root(emulator, adb),
            avd_home: ENV['ANDROID_AVD_HOME'] || default_avd_home,
            source: :external,
            emulator_bin: emulator,
            adb_bin: adb
          )
        end

        candidates
      end

      def find_in_path(name)
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |directory|
          path = File.join(directory, name)
          return path if File.file?(path) && File.executable?(path)
        end
        nil
      end

      def default_avd_home
        base = ENV['ANDROID_EMULATOR_HOME'] || ENV['ANDROID_USER_HOME'] || File.join(Dir.home, '.android')
        File.join(base, 'avd')
      end

      private

      def infer_sdk_root(emulator, adb)
        emulator_root = File.expand_path('..', File.dirname(emulator))
        adb_root = File.expand_path('..', File.dirname(adb))
        emulator_root == adb_root ? emulator_root : nil
      end
    end

    def initialize(sdk_root:, avd_home:, source:, emulator_bin: nil, adb_bin: nil)
      @sdk_root = sdk_root
      @avd_home = avd_home
      @source = source
      @emulator_bin = emulator_bin
      @adb_bin = adb_bin
    end

    def managed?
      source == :managed
    end

    def usable?
      executable?(emulator_bin) && executable?(adb_bin)
    end

    def emulator_bin
      @emulator_bin || File.join(sdk_root.to_s, 'emulator', 'emulator')
    end

    def adb_bin
      @adb_bin || File.join(sdk_root.to_s, 'platform-tools', 'adb')
    end

    def sdkmanager_bin
      File.join(sdk_root.to_s, 'cmdline-tools', 'latest', 'bin', 'sdkmanager')
    end

    def avdmanager_bin
      File.join(sdk_root.to_s, 'cmdline-tools', 'latest', 'bin', 'avdmanager')
    end

    def apk_inspector_bin
      if sdk_root
        tools = Dir.glob(File.join(sdk_root, 'build-tools', '*', 'aapt')).select { |path| executable?(path) }
        return tools.max unless tools.empty?
      end

      self.class.find_in_path('aapt')
    end

    def java_home
      return nil unless managed?

      java = Dir.glob(File.join(self.class.managed_runtime_root, 'current', '**', 'bin', 'java')).find do |path|
        executable?(path)
      end
      java && File.expand_path('..', File.dirname(java))
    end

    def java_bin
      home = java_home
      home && File.join(home, 'bin', 'java')
    end

    def javac_bin
      home = java_home
      home && File.join(home, 'bin', 'javac')
    end

    # A JRE can boot the emulator, but Gradle (React Native/Flutter builds) needs a
    # full JDK. Treat the managed runtime as ready only when javac is present.
    def jdk?
      executable?(javac_bin)
    end

    # Ordered environment exported into the user's shell so external toolchains
    # (`npm run android`, `flutter run`) discover this managed SDK. Managed only.
    def shell_profile_exports
      raise 'shell_profile_exports is only available for the managed toolchain' unless managed?

      home = java_home
      vars = { 'ANDROID_HOME' => sdk_root, 'ANDROID_SDK_ROOT' => sdk_root,
               'ANDROID_AVD_HOME' => avd_home, 'ANDROID_USER_HOME' => self.class.managed_user_home }
      vars['JAVA_HOME'] = home if home
      path_entries = ['platform-tools', 'emulator', File.join('cmdline-tools', 'latest', 'bin')]
                     .map { |dir| File.join(sdk_root, dir) }
      path_entries << File.join(home, 'bin') if home

      [vars, path_entries]
    end

    def environment(include_java: false)
      env = {}
      paths = []

      if sdk_root
        env['ANDROID_HOME'] = sdk_root
        env['ANDROID_SDK_ROOT'] = sdk_root
        paths.concat([
                       File.join(sdk_root, 'emulator'),
                       File.join(sdk_root, 'platform-tools'),
                       File.join(sdk_root, 'cmdline-tools', 'latest', 'bin')
                     ])
      end

      if managed?
        env['ANDROID_AVD_HOME'] = avd_home
        env['ANDROID_USER_HOME'] = self.class.managed_user_home
      end

      if include_java && java_home
        env['JAVA_HOME'] = java_home
        paths.unshift(File.join(java_home, 'bin'))
      elsif invalid_inherited_java_home?
        env['JAVA_HOME'] = nil
      end

      env['PATH'] = (paths + [ENV.fetch('PATH', '')]).uniq.join(File::PATH_SEPARATOR) unless paths.empty?
      env
    end

    def avd_names
      output, _error, status = Open3.capture3(environment, emulator_bin, '-list-avds')
      return [] unless status.success?

      output.lines.map(&:strip).reject(&:empty?)
    end

    def acceleration_status
      return [false, 'Android Emulator is not installed.'] unless executable?(emulator_bin)

      output, error, status = Open3.capture3(environment, emulator_bin, '-accel-check')
      detail = [output, error].join("\n").lines.map(&:strip).reject(&:empty?).join(' ')
      [status.success?, detail]
    end

    private

    def invalid_inherited_java_home?
      home = ENV['JAVA_HOME']
      home && !home.empty? && !executable?(File.join(home, 'bin', 'java'))
    end

    def executable?(path)
      path && File.file?(path) && File.executable?(path)
    end
  end
end
