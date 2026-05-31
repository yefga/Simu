# frozen_string_literal: true

require 'spec_helper'
require 'digest'

RSpec.describe Simu::AndroidInstaller do
  let(:toolchain) { Simu::AndroidToolchain.for_sdk('/opt/android/sdk') }
  let(:prompt) { instance_double(TTY::Prompt) }

  describe '#setup!' do
    it 'installs the SDK packages and creates an AVD in the global SDK location' do
      host = Simu::AndroidToolchain::Host.new(:macos, :arm64)
      sdk = instance_double(
        Simu::AndroidToolchain,
        java_home: '/opt/jdk21',
        sdk_root: '/opt/android/sdk',
        sdkmanager_bin: '/opt/android/sdk/cmdline-tools/latest/bin/sdkmanager',
        usable?: false,
        acceleration_status: [true, 'available']
      )
      installer = described_class.new(prompt: prompt, host: host, toolchain: sdk)
      image = 'system-images;android-36;google_apis;arm64-v8a'
      allow(prompt).to receive(:yes?).and_return(false)
      allow(File).to receive(:executable?).and_call_original
      allow(File).to receive(:executable?).with(sdk.sdkmanager_bin).and_return(true)
      allow(installer).to receive(:preflight!)
      allow(installer).to receive(:confirm_install!)
      allow(installer).to receive(:prepare_directories!)
      allow(installer).to receive(:accept_licenses!)
      allow(installer).to receive(:install_sdk_packages)
      allow(installer).to receive(:select_system_image).and_return(image)
      allow(installer).to receive(:select_device_profile).and_return('pixel_9')
      allow(installer).to receive(:create_or_reuse_avd).and_return('simu_pixel_9_api_36')
      allow(sdk).to receive(:usable?).and_return(false, true)
      allow(Simu::UI).to receive(:success)

      expect(installer.setup!).to eq(sdk)
      expect(installer).to have_received(:install_sdk_packages).with(*described_class::CORE_PACKAGES)
      expect(installer).to have_received(:install_sdk_packages).with(image)
      expect(installer).to have_received(:create_or_reuse_avd).with(image, 'pixel_9')
    end

    it 'aborts with guidance when no adequate JDK is available' do
      host = Simu::AndroidToolchain::Host.new(:macos, :arm64)
      sdk = instance_double(Simu::AndroidToolchain, java_home: nil)
      installer = described_class.new(prompt: prompt, host: host, toolchain: sdk)
      allow(Simu::UI).to receive(:error) { |message| raise message }

      expect { installer.setup! }.to raise_error(/brew install openjdk/)
    end
  end

  describe 'host validation' do
    it 'rejects Linux ARM before performing setup' do
      host = Simu::AndroidToolchain::Host.new(:linux, :arm64)
      installer = described_class.new(prompt: prompt, host: host, toolchain: toolchain)

      expect { installer.send(:ensure_supported_host!) }
        .to raise_error(described_class::SetupError, /does not officially support Linux ARM/)
    end
  end

  describe 'system image selection' do
    it 'filters and ranks compatible stable phone images for Apple silicon' do
      host = Simu::AndroidToolchain::Host.new(:macos, :arm64)
      installer = described_class.new(prompt: prompt, host: host, toolchain: toolchain)
      output = <<~OUTPUT
        system-images;android-36;google_apis_playstore;arm64-v8a | installed
        system-images;android-36;google_apis;arm64-v8a | available
        system-images;android-36;google_apis;x86_64 | available
        system-images;android-35;default;arm64-v8a | available
        system-images;android-35;android-tv;arm64-v8a | available
      OUTPUT

      expect(installer.send(:compatible_images, output)).to eq(
        [
          'system-images;android-36;google_apis;arm64-v8a',
          'system-images;android-36;google_apis_playstore;arm64-v8a',
          'system-images;android-35;default;arm64-v8a'
        ]
      )
    end
  end

  describe 'AVD naming' do
    it 'creates a stable sanitized name from the image and phone profile' do
      host = Simu::AndroidToolchain::Host.new(:macos, :arm64)
      installer = described_class.new(prompt: prompt, host: host, toolchain: toolchain)

      name = installer.send(:avd_name, 'system-images;android-36;google_apis;arm64-v8a', 'Pixel 9 Pro')

      expect(name).to eq('simu_pixel_9_pro_api_36')
    end
  end

  describe 'download progress' do
    it 'updates a spinner with byte percentages while an archive is streamed' do
      host = Simu::AndroidToolchain::Host.new(:macos, :arm64)
      installer = described_class.new(prompt: prompt, host: host, toolchain: toolchain)
      spinner = instance_double(TTY::Spinner, update: nil, auto_spin: nil, success: nil, error: nil)
      response = instance_double(Net::HTTPOK)
      allow(response).to receive(:[]).with('content-length').and_return('4')
      allow(response).to receive(:read_body).and_yield('ab').and_yield('cd')
      allow(TTY::Spinner).to receive(:new).and_return(spinner)
      allow(installer).to receive(:with_http_response).and_yield(response)

      Dir.mktmpdir do |directory|
        destination = File.join(directory, 'archive.zip')
        checksum = Digest::SHA256.hexdigest('abcd')

        installer.send(:download_file, 'https://example.test/archive.zip', destination, checksum, label: 'SDK')

        expect(File.read(destination)).to eq('abcd')
      end

      expect(TTY::Spinner).to have_received(:new).with('[:spinner] Downloading SDK: :progress', format: :classic)
      expect(spinner).to have_received(:update).with(progress: ' 50% (2 B / 4 B)')
      expect(spinner).to have_received(:update).with(progress: '100% (4 B / 4 B)')
      expect(spinner).to have_received(:success).with('Downloaded and verified.')
    end

    it 'reports downloaded bytes when the server omits its total size' do
      host = Simu::AndroidToolchain::Host.new(:macos, :arm64)
      installer = described_class.new(prompt: prompt, host: host, toolchain: toolchain)

      expect(installer.send(:download_progress, 1024)).to eq('1 KB downloaded')
    end
  end
end
