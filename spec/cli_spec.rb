# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Simu::CLI do
  describe '#list' do
    it 'does not invoke Apple discovery when listing devices on Linux' do
      linux = Simu::AndroidToolchain::Host.new(:linux, :x86_64)
      allow(Simu::AndroidToolchain).to receive(:host).and_return(linux)
      android = instance_double(Simu::Android, get_all_avds: [])
      allow(Simu::Android).to receive(:new).and_return(android)
      allow(TTY::Spinner).to receive(:new).and_return(instance_double(TTY::Spinner, auto_spin: nil, success: nil))
      expect(Simu::Apple).not_to receive(:new)

      expect { described_class.new.list }.to output(/showing Android emulators only/).to_stdout
    end
  end
end
