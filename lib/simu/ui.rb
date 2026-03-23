# frozen_string_literal: true

require 'pastel'
require 'tty-spinner'
require 'tty-prompt'
require 'terminal-table'

module Simu
  class UI
    class << self
      def pastel
        @pastel ||= Pastel.new
      end

      def prompt
        @prompt ||= TTY::Prompt.new
      end

      def error(message)
        puts pastel.red.bold("Error: #{message}")
        exit 1
      end

      def success(message)
        puts pastel.green(message)
      end

      def info(message)
        puts pastel.cyan(message)
      end

      def doctor_success(message)
        puts pastel.green("[✓] #{message}")
      end

      def doctor_error(message)
        puts pastel.red("[✗] #{message}")
      end

      def render_table(title:, headings:, rows:)
        return puts pastel.yellow("No records found for #{title}.") if rows.empty?

        table = Terminal::Table.new do |t|
          t.title = pastel.bold(title)
          t.headings = headings.map { |h| pastel.bold(h) }
          t.rows = rows
          t.style = { border: :unicode, alignment: :center }
        end
        puts table
      end
    end
  end
end
