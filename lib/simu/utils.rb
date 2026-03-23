# frozen_string_literal: true

module Simu
  module Utils
    def self.format_size(bytes)
      return 'N/A' if bytes.nil? || bytes <= 0

      units = %w[B KB MB GB TB]
      e = (Math.log(bytes) / Math.log(1024)).floor
      s = format('%.2f %s', bytes.to_f / (1024**e), units[e])
      s.sub('.00', '')
    end

    def self.dir_size(path)
      return 0 unless File.directory?(path)

      # Use du -sk for high-speed directory size computation
      output = `du -sk "#{path}" 2>/dev/null`.strip
      return 0 if output.empty?

      kb_size = output.split(/\s+/).first.to_i
      kb_size * 1024
    end
  end
end
