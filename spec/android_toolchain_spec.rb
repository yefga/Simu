# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Simu::AndroidToolchain do
  def executable(path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "#!/bin/sh\nexit 0\n")
    FileUtils.chmod(0o755, path)
  end

  def jdk(home, version)
    executable(File.join(home, 'bin', 'java'))
    executable(File.join(home, 'bin', 'javac'))
    File.write(File.join(home, 'release'), %(JAVA_VERSION="#{version}"\n))
    home
  end

  around do |example|
    old = ENV.to_hash.slice('HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'ANDROID_AVD_HOME',
                            'ANDROID_USER_HOME', 'JAVA_HOME', 'PATH')

    Dir.mktmpdir do |directory|
      ENV['HOME'] = File.join(directory, 'home')
      %w[ANDROID_HOME ANDROID_SDK_ROOT ANDROID_AVD_HOME ANDROID_USER_HOME JAVA_HOME].each { |k| ENV[k] = nil }
      ENV['PATH'] = ''
      FileUtils.mkdir_p(ENV['HOME'])
      example.run
    end
  ensure
    old.each { |key, value| ENV[key] = value }
  end

  let(:macos) { described_class::Host.new(:macos, :arm64) }

  describe '.supported_host?' do
    it 'supports macOS architectures and Linux x86_64 only' do
      expect(described_class.supported_host?(described_class::Host.new(:macos, :arm64))).to be(true)
      expect(described_class.supported_host?(described_class::Host.new(:macos, :x86_64))).to be(true)
      expect(described_class.supported_host?(described_class::Host.new(:linux, :x86_64))).to be(true)
      expect(described_class.supported_host?(described_class::Host.new(:linux, :arm64))).to be(false)
    end
  end

  describe '.sdk_root' do
    it 'defaults to the canonical macOS SDK path' do
      expect(described_class.sdk_root(macos)).to eq(File.join(ENV['HOME'], 'Library', 'Android', 'sdk'))
    end

    it 'honors $ANDROID_HOME, then $ANDROID_SDK_ROOT' do
      ENV['ANDROID_SDK_ROOT'] = '/opt/sdk-root'
      expect(described_class.sdk_root(macos)).to eq('/opt/sdk-root')

      ENV['ANDROID_HOME'] = '/opt/sdk-home'
      expect(described_class.sdk_root(macos)).to eq('/opt/sdk-home')
    end
  end

  describe '.avd_home' do
    it 'defaults to the standard ~/.android/avd location' do
      expect(described_class.avd_home).to eq(File.join(ENV['HOME'], '.android', 'avd'))
    end
  end

  describe '.java_home' do
    it 'reuses an adequate $JAVA_HOME' do
      home = jdk(File.join(ENV['HOME'], 'jdk21'), '21.0.1')
      ENV['JAVA_HOME'] = home

      expect(described_class.java_home).to eq(home)
    end

    it 'rejects a JDK below the minimum and finds none' do
      ENV['JAVA_HOME'] = jdk(File.join(ENV['HOME'], 'jdk11'), '11.0.20')
      allow(described_class).to receive(:macos_java_home).and_return(nil)

      expect(described_class.java_home).to be_nil
    end

    it 'rejects a JRE (java without javac)' do
      home = File.join(ENV['HOME'], 'jre17')
      executable(File.join(home, 'bin', 'java'))
      ENV['JAVA_HOME'] = home
      allow(described_class).to receive(:macos_java_home).and_return(nil)

      expect(described_class.java_home).to be_nil
    end
  end

  describe '.resolve' do
    it 'returns the global SDK when adb and emulator are present' do
      sdk = described_class.sdk_root(macos)
      executable(File.join(sdk, 'emulator', 'emulator'))
      executable(File.join(sdk, 'platform-tools', 'adb'))
      ENV['ANDROID_HOME'] = sdk

      toolchain = described_class.resolve

      expect(toolchain.sdk_root).to eq(sdk)
      expect(toolchain.usable?).to be(true)
    end

    it 'is nil when no usable SDK exists' do
      expect(described_class.resolve).to be_nil
    end
  end

  describe '#environment' do
    it 'injects the SDK paths and adds Java only for provisioning commands' do
      home = jdk(File.join(ENV['HOME'], 'jdk21'), '21.0.1')
      ENV['JAVA_HOME'] = home
      toolchain = described_class.for_sdk('/opt/sdk')

      runtime_env = toolchain.environment
      setup_env = toolchain.environment(include_java: true)

      expect(runtime_env).to include('ANDROID_HOME' => '/opt/sdk', 'ANDROID_SDK_ROOT' => '/opt/sdk')
      expect(runtime_env).not_to have_key('JAVA_HOME')
      expect(setup_env['JAVA_HOME']).to eq(home)
    end

    it 'drops an inherited JAVA_HOME that does not contain an executable Java runtime' do
      ENV['JAVA_HOME'] = File.join(ENV['HOME'], 'missing-jdk')
      toolchain = described_class.for_sdk('/opt/sdk')

      expect(toolchain.environment).to include('JAVA_HOME' => nil)
    end
  end

  describe '#shell_profile_exports' do
    it 'exports the SDK and discovered JDK paths for external toolchains' do
      home = jdk(File.join(ENV['HOME'], 'jdk21'), '21.0.1')
      ENV['JAVA_HOME'] = home
      toolchain = described_class.for_sdk('/opt/sdk')

      vars, path_entries = toolchain.shell_profile_exports

      expect(vars).to include('ANDROID_HOME' => '/opt/sdk', 'ANDROID_SDK_ROOT' => '/opt/sdk', 'JAVA_HOME' => home)
      expect(path_entries).to include(
        '/opt/sdk/platform-tools',
        '/opt/sdk/emulator',
        '/opt/sdk/cmdline-tools/latest/bin',
        File.join(home, 'bin')
      )
    end
  end
end
