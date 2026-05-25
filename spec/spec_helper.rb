# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'simu'

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
end
