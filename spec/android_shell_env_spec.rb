# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Simu::AndroidShellEnv do
  around do |example|
    old = ENV.to_hash.slice('HOME', 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'PATH', 'SHELL')
    Dir.mktmpdir do |directory|
      ENV['HOME'] = File.join(directory, 'home')
      ENV['ANDROID_HOME'] = nil
      ENV['ANDROID_SDK_ROOT'] = nil
      ENV['PATH'] = ''
      ENV['SHELL'] = '/bin/zsh'
      FileUtils.mkdir_p(ENV['HOME'])
      example.run
    end
  ensure
    old.each { |key, value| ENV[key] = value }
  end

  let(:toolchain) do
    instance_double(
      Simu::AndroidToolchain,
      shell_profile_exports: [
        { 'ANDROID_HOME' => '/sdk', 'JAVA_HOME' => '/jdk' },
        ['/sdk/platform-tools', '/jdk/bin']
      ]
    )
  end

  describe '.export_script' do
    it 'renders ordered exports and preserves the inherited PATH' do
      script = described_class.export_script(toolchain)

      expect(script).to include('export ANDROID_HOME="/sdk"')
      expect(script).to include('export JAVA_HOME="/jdk"')
      expect(script).to include(%(export PATH="/sdk/platform-tools#{File::PATH_SEPARATOR}/jdk/bin#{File::PATH_SEPARATOR}$PATH"))
    end
  end

  describe '.apply!' do
    it 'writes a marker-bounded export block into ~/.zshrc' do
      zshrc = File.join(ENV['HOME'], '.zshrc')
      File.write(zshrc, "# existing config\n")

      updated = described_class.apply!(toolchain)

      expect(updated).to eq([zshrc])
      body = File.read(zshrc)
      expect(body).to start_with("# existing config\n")
      expect(body).to include(described_class::BEGIN_MARKER)
      expect(body).to include('export ANDROID_HOME="/sdk"')
      expect(body).to include(described_class::END_MARKER)
    end

    it 'is idempotent across repeated runs' do
      zshrc = File.join(ENV['HOME'], '.zshrc')

      described_class.apply!(toolchain)
      first = File.read(zshrc)
      second_updates = described_class.apply!(toolchain)

      expect(second_updates).to be_empty
      expect(File.read(zshrc)).to eq(first)
      expect(first.scan(described_class::BEGIN_MARKER).length).to eq(1)
    end

    it 'replaces an existing block when exports change' do
      zshrc = File.join(ENV['HOME'], '.zshrc')
      described_class.apply!(toolchain)

      changed = instance_double(
        Simu::AndroidToolchain,
        shell_profile_exports: [{ 'ANDROID_HOME' => '/new-sdk' }, ['/new-sdk/platform-tools']]
      )
      described_class.apply!(changed)

      body = File.read(zshrc)
      expect(body).to include('export ANDROID_HOME="/new-sdk"')
      expect(body).not_to include('/sdk/platform-tools')
      expect(body.scan(described_class::BEGIN_MARKER).length).to eq(1)
    end
  end

  describe '.profile_paths' do
    it 'targets ~/.zshrc for a zsh login shell' do
      ENV['SHELL'] = '/bin/zsh'
      expect(described_class.profile_paths).to eq([File.join(ENV['HOME'], '.zshrc')])
    end

    it 'targets the bash profile (creating it) when the login shell is bash' do
      ENV['SHELL'] = '/bin/bash'
      allow(Simu::AndroidToolchain).to receive(:host)
        .and_return(Simu::AndroidToolchain::Host.new(:macos, :arm64))

      expect(described_class.profile_paths).to include(File.join(ENV['HOME'], '.bash_profile'))
      expect(described_class.profile_paths).not_to include(File.join(ENV['HOME'], '.zshrc'))
    end

    it 'also updates other standard profiles that already exist' do
      ENV['SHELL'] = '/bin/zsh'
      bashrc = File.join(ENV['HOME'], '.bashrc')
      File.write(bashrc, "# bash\n")

      expect(described_class.profile_paths).to include(File.join(ENV['HOME'], '.zshrc'), bashrc)
    end
  end

  describe '.configured?' do
    it 'is true once the marker block is present' do
      expect(described_class.configured?).to be(false)
      described_class.apply!(toolchain)
      expect(described_class.configured?).to be(true)
    end
  end
end
