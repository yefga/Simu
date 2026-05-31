# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Simu::AndroidShellEnv do
  around do |example|
    old_home = ENV['HOME']
    old_simu_home = ENV['SIMU_HOME']

    Dir.mktmpdir do |directory|
      ENV['HOME'] = File.join(directory, 'home')
      ENV['SIMU_HOME'] = File.join(directory, 'simu')
      FileUtils.mkdir_p(ENV['HOME'])
      example.run
    end
  ensure
    ENV['HOME'] = old_home
    ENV['SIMU_HOME'] = old_simu_home
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

  describe '.env_file_contents' do
    it 'renders ordered exports and preserves the inherited PATH' do
      contents = described_class.env_file_contents(toolchain)

      expect(contents).to include('export ANDROID_HOME="/sdk"')
      expect(contents).to include('export JAVA_HOME="/jdk"')
      expect(contents).to include(%(export PATH="/sdk/platform-tools#{File::PATH_SEPARATOR}/jdk/bin#{File::PATH_SEPARATOR}$PATH"))
    end
  end

  describe '.apply!' do
    it 'writes the env file and a marker-bounded sourcing block into ~/.zshrc' do
      zshrc = File.join(ENV['HOME'], '.zshrc')
      File.write(zshrc, "# existing config\n")

      updated = described_class.apply!(toolchain)

      expect(updated).to eq([zshrc])
      expect(File.read(described_class.env_file)).to include('export ANDROID_HOME="/sdk"')
      body = File.read(zshrc)
      expect(body).to start_with("# existing config\n")
      expect(body).to include(described_class::BEGIN_MARKER)
      expect(body).to include(%([ -f "#{described_class.env_file}" ] && . "#{described_class.env_file}"))
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
  end
end
