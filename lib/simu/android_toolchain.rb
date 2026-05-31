# frozen_string_literal: true

require 'open3'
require 'rbconfig'

module Simu
  # Resolves the global Android SDK location and a usable host JDK. Simu installs
  # into the canonical SDK path (honoring $ANDROID_HOME/$ANDROID_SDK_ROOT) and
  # reuses an existing JDK rather than keeping a private copy of either.
  class AndroidToolchain
    Host = Struct.new(:os, :arch) do
      def label
        "#{os} #{arch}"
      end
    end

    MINIMUM_JDK_MAJOR = 17

    attr_reader :sdk_root, :avd_home

    class << self
      def host
        os = case RbConfig::CONFIG['host_os']
             when /darwin/ then :macos
             when /linux/ then :linux
             else :unsupported
             end
        arch = case RbConfig::CONFIG['host_cpu']
               when /arm64|aarch64/ then :arm64
               when /x86_64|amd64/ then :x86_64
               else :unsupported
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

      # The Android SDK location: an explicit $ANDROID_HOME/$ANDROID_SDK_ROOT wins,
      # otherwise the canonical per-OS default that Android Studio/RN/Flutter expect.
      def sdk_root(candidate = host)
        configured = [ENV['ANDROID_HOME'], ENV['ANDROID_SDK_ROOT']].find { |value| value && !value.empty? }
        return File.expand_path(configured) if configured

        default_sdk_root(candidate)
      end

      def default_sdk_root(candidate = host)
        if candidate.os == :macos
          File.join(Dir.home, 'Library', 'Android', 'sdk')
        else
          File.join(Dir.home, 'Android', 'Sdk')
        end
      end

      # AVDs live in the standard location so every tool (Android Studio, RN,
      # Flutter) sees the same virtual devices.
      def avd_home
        configured = ENV['ANDROID_AVD_HOME']
        return File.expand_path(configured) if configured && !configured.empty?

        File.join(user_home, 'avd')
      end

      def user_home
        configured = ENV['ANDROID_USER_HOME']
        return File.expand_path(configured) if configured && !configured.empty?

        File.join(Dir.home, '.android')
      end

      def for_sdk(root = sdk_root)
        new(sdk_root: root, avd_home: avd_home)
      end

      # A usable toolchain is the global SDK when it carries adb + emulator, or
      # tools already discoverable on PATH.
      def resolve
        candidate = for_sdk
        return candidate if candidate.usable?

        emulator = find_in_path('emulator')
        adb = find_in_path('adb')
        return nil unless emulator && adb

        new(sdk_root: infer_sdk_root(emulator, adb) || sdk_root, avd_home: avd_home,
            emulator_bin: emulator, adb_bin: adb)
      end

      def find_in_path(name)
        ENV.fetch('PATH', '').split(File::PATH_SEPARATOR).each do |directory|
          path = File.join(directory, name)
          return path if File.file?(path) && File.executable?(path)
        end
        nil
      end

      # Discovers a host JDK (>= MINIMUM_JDK_MAJOR): an adequate $JAVA_HOME first,
      # then /usr/libexec/java_home on macOS, then javac on PATH. Never installs.
      def java_home
        env = ENV['JAVA_HOME']
        env = File.expand_path(env) if env && !env.empty?
        return env if env && !env.empty? && adequate_jdk?(env)

        macos = host.os == :macos ? macos_java_home : nil
        return macos if macos && adequate_jdk?(macos)

        path_home = path_javac_home
        path_home if path_home && adequate_jdk?(path_home)
      end

      def adequate_jdk?(home)
        return false unless home

        javac = File.join(home, 'bin', 'javac')
        return false unless File.file?(javac) && File.executable?(javac)

        major = jdk_major(home)
        major ? major >= MINIMUM_JDK_MAJOR : false
      end

      private

      def macos_java_home
        output, _error, status = Open3.capture3('/usr/libexec/java_home', '-v', "#{MINIMUM_JDK_MAJOR}+")
        status.success? ? output.strip : nil
      rescue Errno::ENOENT
        nil
      end

      def path_javac_home
        javac = find_in_path('javac')
        javac && File.expand_path('..', File.dirname(javac))
      end

      def jdk_major(home)
        version = jdk_version_string(home)
        return nil unless version

        match = version.match(/(\d+)(?:\.(\d+))?/)
        return nil unless match

        major = match[1].to_i
        major == 1 ? match[2].to_i : major
      end

      def jdk_version_string(home)
        release = File.join(home, 'release')
        if File.file?(release) && (match = File.read(release).match(/JAVA_VERSION="?([\d._]+)/))
          return match[1]
        end

        javac = File.join(home, 'bin', 'javac')
        return nil unless File.executable?(javac)

        output, error, status = Open3.capture3(javac, '-version')
        status.success? ? "#{output}#{error}"[/javac\s+([\d._]+)/, 1] : nil
      rescue StandardError
        nil
      end

      def infer_sdk_root(emulator, adb)
        emulator_root = File.expand_path('..', File.dirname(emulator))
        adb_root = File.expand_path('..', File.dirname(adb))
        emulator_root == adb_root ? emulator_root : nil
      end
    end

    def initialize(sdk_root:, avd_home:, emulator_bin: nil, adb_bin: nil)
      @sdk_root = sdk_root
      @avd_home = avd_home
      @emulator_bin = emulator_bin
      @adb_bin = adb_bin
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
      self.class.java_home
    end

    def java_bin
      home = java_home
      home && File.join(home, 'bin', 'java')
    end

    def javac_bin
      home = java_home
      home && File.join(home, 'bin', 'javac')
    end

    # A discoverable JDK (>= MINIMUM_JDK_MAJOR) is what Gradle needs for
    # React Native/Flutter builds.
    def jdk?
      !java_home.nil?
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

      if include_java && (home = java_home)
        env['JAVA_HOME'] = home
        paths.unshift(File.join(home, 'bin'))
      elsif invalid_inherited_java_home?
        env['JAVA_HOME'] = nil
      end

      env['PATH'] = (paths + [ENV.fetch('PATH', '')]).uniq.join(File::PATH_SEPARATOR) unless paths.empty?
      env
    end

    # Ordered exports written into the user's shell so external toolchains
    # (`npm run android`, `flutter run`) discover this SDK and JDK.
    def shell_profile_exports
      vars = { 'ANDROID_HOME' => sdk_root, 'ANDROID_SDK_ROOT' => sdk_root }
      path_entries = ['platform-tools', 'emulator', File.join('cmdline-tools', 'latest', 'bin')]
                     .map { |dir| File.join(sdk_root, dir) }
      if (home = java_home)
        vars['JAVA_HOME'] = home
        path_entries << File.join(home, 'bin')
      end

      [vars, path_entries]
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
