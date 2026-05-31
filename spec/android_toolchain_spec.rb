# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Simu::AndroidToolchain do
  def executable(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, path)
  end

  around do |example|
    old_home = ENV['HOME']
    old_simu_home = ENV['SIMU_HOME']
    old_android_home = ENV['ANDROID_HOME']
    old_sdk_root = ENV['ANDROID_SDK_ROOT']
    old_java_home = ENV['JAVA_HOME']
    old_path = ENV['PATH']

    Dir.mktmpdir do |directory|
      ENV['HOME'] = File.join(directory, 'home')
      ENV['SIMU_HOME'] = File.join(directory, 'simu')
      ENV['ANDROID_HOME'] = nil
      ENV['ANDROID_SDK_ROOT'] = nil
      ENV['JAVA_HOME'] = nil
      ENV['PATH'] = ''
      FileUtils.mkdir_p(ENV['HOME'])
      example.run
    end
  ensure
    ENV['HOME'] = old_home
    ENV['SIMU_HOME'] = old_simu_home
    ENV['ANDROID_HOME'] = old_android_home
    ENV['ANDROID_SDK_ROOT'] = old_sdk_root
    ENV['JAVA_HOME'] = old_java_home
    ENV['PATH'] = old_path
  end

  describe '.supported_host?' do
    it 'supports macOS architectures and Linux x86_64 only' do
      expect(described_class.supported_host?(described_class::Host.new(:macos, :arm64))).to be(true)
      expect(described_class.supported_host?(described_class::Host.new(:macos, :x86_64))).to be(true)
      expect(described_class.supported_host?(described_class::Host.new(:linux, :x86_64))).to be(true)
      expect(described_class.supported_host?(described_class::Host.new(:linux, :arm64))).to be(false)
    end
  end

  describe '.resolve' do
    it 'prefers a usable externally configured SDK over the managed SDK' do
      external = File.join(ENV['HOME'], 'external-sdk')
      managed = described_class.managed_sdk_root
      executable(File.join(external, 'emulator', 'emulator'))
      executable(File.join(external, 'platform-tools', 'adb'))
      executable(File.join(managed, 'emulator', 'emulator'))
      executable(File.join(managed, 'platform-tools', 'adb'))
      ENV['ANDROID_HOME'] = external

      toolchain = described_class.resolve

      expect(toolchain.source).to eq(:external)
      expect(toolchain.sdk_root).to eq(external)
    end
  end

  describe '#environment' do
    it 'injects managed Android paths but Java only for provisioning commands' do
      java = File.join(described_class.managed_runtime_root, 'current', 'jdk', 'bin', 'java')
      executable(java)
      toolchain = described_class.managed

      runtime_env = toolchain.environment
      setup_env = toolchain.environment(include_java: true)

      expect(runtime_env).to include(
        'ANDROID_HOME' => described_class.managed_sdk_root,
        'ANDROID_AVD_HOME' => described_class.managed_avd_home
      )
      expect(runtime_env).not_to have_key('JAVA_HOME')
      expect(setup_env['JAVA_HOME']).to eq(File.dirname(File.dirname(java)))
    end

    it 'drops an inherited JAVA_HOME that does not contain an executable Java runtime' do
      ENV['JAVA_HOME'] = File.join(ENV['HOME'], 'missing-jdk')
      toolchain = described_class.managed

      expect(toolchain.environment).to include('JAVA_HOME' => nil)
    end
  end

  describe '#jdk?' do
    it 'is false for a JRE (java without javac) and true once javac is present' do
      java = File.join(described_class.managed_runtime_root, 'current', 'jdk', 'bin', 'java')
      executable(java)
      toolchain = described_class.managed
      expect(toolchain.jdk?).to be(false)

      executable(File.join(described_class.managed_runtime_root, 'current', 'jdk', 'bin', 'javac'))
      expect(toolchain.jdk?).to be(true)
    end
  end

  describe '#shell_profile_exports' do
    it 'exports managed SDK and JDK paths for external toolchains' do
      executable(File.join(described_class.managed_runtime_root, 'current', 'jdk', 'bin', 'java'))
      toolchain = described_class.managed

      vars, path_entries = toolchain.shell_profile_exports

      sdk = described_class.managed_sdk_root
      expect(vars).to include(
        'ANDROID_HOME' => sdk,
        'ANDROID_SDK_ROOT' => sdk,
        'ANDROID_AVD_HOME' => described_class.managed_avd_home,
        'JAVA_HOME' => File.join(described_class.managed_runtime_root, 'current', 'jdk')
      )
      expect(path_entries).to include(
        File.join(sdk, 'platform-tools'),
        File.join(sdk, 'emulator'),
        File.join(sdk, 'cmdline-tools', 'latest', 'bin'),
        File.join(described_class.managed_runtime_root, 'current', 'jdk', 'bin')
      )
    end
  end
end
