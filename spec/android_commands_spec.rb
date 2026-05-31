# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Simu::Android do
  describe '#launch_path' do
    it 'launches the selected emulator without building the current directory when no path is given' do
      toolchain = instance_double(Simu::AndroidToolchain)
      prompt = instance_double(TTY::Prompt)
      allow(Simu::Setup).to receive(:ensure_android_tools!).and_return(toolchain)
      allow(Simu::UI).to receive(:prompt).and_return(prompt)
      allow(prompt).to receive(:select).and_return('simu_pixel_9a_api_36')
      android = described_class.new
      allow(android).to receive(:get_all_avds).with(toolchain).and_return(
        [{ name: 'simu_pixel_9a_api_36', api: '36', state: 'Ready', size: 'N/A' }]
      )
      allow(android).to receive(:boot_emulator)
      allow(android).to receive(:wait_for_emulator_boot)
      allow(android).to receive(:build_and_launch_android_project)

      android.launch_path

      expect(android).to have_received(:boot_emulator).with(toolchain, 'simu_pixel_9a_api_36')
      expect(android).not_to have_received(:wait_for_emulator_boot)
      expect(android).not_to have_received(:build_and_launch_android_project)
    end
  end

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
