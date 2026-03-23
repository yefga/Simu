# frozen_string_literal: true

require 'thor'
require_relative 'simu/version'
require_relative 'simu/ui'
require_relative 'simu/utils'
require_relative 'simu/setup'
require_relative 'simu/apple'
require_relative 'simu/android'
require_relative 'simu/cli'

module Simu
  class Error < StandardError; end
end
