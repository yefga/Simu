# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Simu::Android do
  describe '#exec_command' do
    it 'runs a framework command with the Android environment and without managed Java' do
      toolchain = instance_double(Simu::AndroidToolchain, environment: { 'ANDROID_HOME' => '/managed/sdk' })
      allow(Simu::Setup).to receive(:ensure_android_tools!).and_return(toolchain)
      android = described_class.new
      allow(android).to receive(:system).with({ 'ANDROID_HOME' => '/managed/sdk' }, 'flutter', 'run').and_return(true)

      android.exec_command('--', 'flutter', 'run')

      expect(android).to have_received(:system).with({ 'ANDROID_HOME' => '/managed/sdk' }, 'flutter', 'run')
    end
  end
end

RSpec.describe Simu::Setup do
  describe '.ensure_android_tools!' do
    it 'instructs users to run doctor and setup instead of installing Android Studio' do
      allow(Simu::AndroidToolchain).to receive(:host).and_return(Simu::AndroidToolchain::Host.new(:macos, :arm64))
      allow(Simu::AndroidToolchain).to receive(:supported_host?).and_return(true)
      allow(Simu::AndroidToolchain).to receive(:resolve).and_return(nil)
      allow(Simu::UI).to receive(:error) { |message| raise message }

      expect { described_class.ensure_android_tools! }
        .to raise_error(RuntimeError, /simu android doctor.*simu android setup/)
    end
  end
end
