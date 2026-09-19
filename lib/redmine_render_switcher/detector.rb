# frozen_string_literal: true

require_relative "logger"

module RedmineRenderSwitcher
  # Decides whether a text is written in Textile or in Markdown by scoring the
  # notation it uses.
  #
  # The detector knows nothing about the explicit directive: {AutoSwitch} evaluates
  # that first and only falls through to here, which keeps this module responsible
  # for exactly one thing.
  #
  # Detection runs in four steps: code blocks are masked out, the frozen pattern
  # tables add up a score for each format, the +#+ line-context rule resolves the
  # one notation the two formats disagree about, and the threshold decides whether
  # the margin is wide enough to name a winner.
  module Detector
    extend RedmineRenderSwitcher::Logger

    # Generation of the detection logic.
    #
    # {CacheKey} mixes this into the formatted-HTML cache key, so a change to the
    # pattern table, to the context rule or to code-block masking MUST bump this
    # constant in the same change set. Forgetting to is a defect: old HTML would
    # keep being served for texts whose verdict has changed.
    VERSION = 1

    # Redmine's name for the Textile format.
    TEXTILE = "textile"

    # Redmine's name for the Markdown format.
    COMMON_MARK = "common_mark"

    # The outcome of one detection.
    #
    # It carries the verdict and the evidence behind it, and deliberately does not
    # carry the text, so that logging a result can never leak page content.
    #
    # @!attribute [r] format
    #   @return [String, nil] {TEXTILE}, {COMMON_MARK}, or nil when undecided.
    # @!attribute [r] textile_score
    #   @return [Integer] how much the text looks like Textile.
    # @!attribute [r] markdown_score
    #   @return [Integer] how much the text looks like Markdown.
    # @!attribute [r] reason
    #   @return [Symbol] :directive, :score, :below_threshold or :no_signal.
    Result = Data.define(:format, :textile_score, :markdown_score, :reason) do
      # One line naming the verdict and the evidence behind it, for the debug log.
      #
      # The text itself is deliberately absent, so that turning debug logging on
      # can never spill page content into the log.
      #
      # @return [String] the verdict and both scores.
      def to_log
        "format=#{format || "none"} textile_score=#{textile_score} " \
          "markdown_score=#{markdown_score} reason=#{reason}"
      end
    end

    # Notation that only Textile gives meaning to, with its weight.
    #
    # Notation both formats read the same way (+* list+, +> quote+, +|table|+) is
    # absent on purpose: getting it wrong changes no rendered output, so moving the
    # score on it buys nothing.
    TEXTILE_PATTERNS = {
      /^h[1-6]\.\s/ => 5,
      /"[^"\n]+":\S+/ => 4,
      %r{!\S*[./]\S*!} => 3,
      /^bq\.\s/ => 4,
      /@[^@\s][^@\n]*@/ => 3,
      /^\|_\./ => 5
    }.freeze

    # Notation that only Markdown gives meaning to, with its weight.
    MARKDOWN_PATTERNS = {
      /^[ \t]*(?:```|~~~)/ => 5,
      /!\[[^\]\n]*\]\([^)\n]*\)/ => 4,
      /\[[^\]\n]*\]\([^)\n]*\)/ => 4,
      /\*\*[^*\n]+\*\*/ => 3,
      /`[^`\n]+`/ => 3,
      /^\|[\s:|-]*-[\s:|-]*\|/ => 5
    }.freeze

    # A line opening or closing a Markdown fenced code block.
    FENCE_LINE = /\A[ \t]*(?:```|~~~)/

    # The opening tag of an HTML preformatted block.
    PRE_OPEN = /<pre\b/i

    # The closing tag of an HTML preformatted block.
    PRE_CLOSE = %r{</pre>}i

    # A line that starts with one or more +#+ followed by a space.
    #
    # Textile reads it as an ordered-list item, Markdown as a heading. This is the
    # only head-on collision between the two formats, and {.score_hash_lines}
    # resolves it by looking at the lines around it.
    HASH_LINE = /\A#+(?:[ \t]|$)/

    # Added to the Textile score for each line of a run of +#+ lines.
    HASH_RUN_TEXTILE_WEIGHT = 5

    # Added to the Markdown score for a +#+ line that stands on its own.
    HASH_HEADING_MARKDOWN_WEIGHT = 4

    class << self
      # Detects the format +text+ is written in.
      #
      # @param text [String] the text to inspect. It is never modified.
      # @param threshold [Integer] the score difference the winner must reach.
      # @return [Result] always a result, never nil.
      def detect(text, threshold:)
        masked = mask_code_blocks(text)
        hash_textile, hash_markdown = score_hash_lines(masked.lines)

        result = build_result(
          score(masked, TEXTILE_PATTERNS) + hash_textile,
          score(masked, MARKDOWN_PATTERNS) + hash_markdown,
          threshold
        )
        render_switcher_logger.debug { "detected #{result.to_log}" }

        result
      end

      private

      # Blanks out what lives inside a code block, so that a Textile snippet quoted
      # in a Markdown document (or the other way round) cannot sway the verdict.
      #
      # Fence lines themselves are kept, because a fence is Markdown evidence in its
      # own right. The work happens on a copy; +text+ is left alone (FR-007).
      #
      # @param text [String] the original text.
      # @return [String] a copy with code-block contents replaced by blank lines.
      def mask_code_blocks(text)
        in_fence = false
        in_pre = false

        text.lines.map do |line|
          fence = FENCE_LINE.match?(line)
          if in_fence
            in_fence = false if fence
            next(fence ? line : "\n")
          end
          if in_pre
            in_pre = false if PRE_CLOSE.match?(line)
            next "\n"
          end
          if fence
            in_fence = true
            next line
          end
          if PRE_OPEN.match?(line)
            in_pre = true unless PRE_CLOSE.match?(line)
            next "\n"
          end

          line
        end.join
      end

      # Adds up one side of the score.
      #
      # @param text [String] the masked text.
      # @param patterns [Hash{Regexp => Integer}] the rule table to apply.
      # @return [Integer] the total score.
      def score(text, patterns)
        patterns.sum { |pattern, weight| text.scan(pattern).size * weight }
      end

      # Resolves the +#+ collision by line context rather than by more patterns.
      #
      # Two or more +#+ lines in a row are a Textile ordered list; a +#+ line on its
      # own is a Markdown heading. Adding patterns here instead would only make the
      # detector guess harder at the same ambiguity.
      #
      # @param lines [Array<String>] the lines of the masked text.
      # @return [Array(Integer, Integer)] the Textile and Markdown scores.
      def score_hash_lines(lines)
        textile = 0
        markdown = 0
        run = 0

        (lines + [ "" ]).each do |line|
          if HASH_LINE.match?(line)
            run += 1
            next
          end

          textile += run * HASH_RUN_TEXTILE_WEIGHT if run >= 2
          markdown += HASH_HEADING_MARKDOWN_WEIGHT if run == 1
          run = 0
        end

        [ textile, markdown ]
      end

      # Turns the two scores into a verdict.
      #
      # @param textile [Integer] the Textile score.
      # @param markdown [Integer] the Markdown score.
      # @param threshold [Integer] the margin the winner must reach.
      # @return [Result] the verdict together with the evidence.
      def build_result(textile, markdown, threshold)
        reason =
          if textile.zero? && markdown.zero?
            :no_signal
          elsif (textile - markdown).abs < threshold
            :below_threshold
          else
            :score
          end
        format = reason == :score ? (textile > markdown ? TEXTILE : COMMON_MARK) : nil

        Result.new(format: format, textile_score: textile, markdown_score: markdown, reason: reason)
      end
    end
  end
end
