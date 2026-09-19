# frozen_string_literal: true

require_relative "detector"

module RedmineRenderSwitcher
  # Reads the explicit format override an author can put on the first line of a
  # text, for the pages the scoring detector gets wrong.
  #
  #   <!-- render_switcher: textile -->
  #   <!-- render_switcher: markdown -->
  #
  # An HTML comment is used rather than a +{{...}}+ macro on purpose. Redmine runs
  # +catch_macros+ before rendering and rewrites any macro it recognises to
  # +{{macro(0)}}+, which would destroy the very string this parser reads; and both
  # renderers drop HTML comments from their output, so the directive stays off the
  # screen with no stripping code — and therefore no stripping code to delete the
  # line on every section save.
  module Directive
    # The one accepted spelling. Whitespace inside the comment and the case of the
    # format name may vary; nothing else is accepted.
    PATTERN = /\A<!--\s*render_switcher\s*:\s*(textile|markdown)\s*-->\s*\z/i

    # The two words an author writes, mapped to the names Redmine uses. This is the
    # only place "markdown" becomes "common_mark".
    FORMAT_BY_NAME = {
      "textile" => Detector::TEXTILE,
      "markdown" => Detector::COMMON_MARK
    }.freeze

    # Reads the directive off the first line of +text+.
    #
    # Only the first line counts, so the same string quoted further down the page
    # has no effect. +text+ is never modified.
    #
    # @param text [String] the body to inspect.
    # @return [String, nil] {Detector::TEXTILE}, {Detector::COMMON_MARK}, or nil
    #   when the first line is not a directive.
    def self.parse(text)
      match = PATTERN.match(text[/\A.*/])
      return nil unless match

      FORMAT_BY_NAME[match[1].downcase]
    end
  end
end
