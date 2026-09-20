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
  # Detection runs in four steps: code blocks (fenced, +<pre>+ and indented) are
  # masked out, the frozen pattern tables add up a score for each format, the
  # line-context rules (+#+ lines, lists, tables and Setext headings) score what
  # only the lines around a line can settle, and the threshold decides whether the
  # margin is wide enough to name a winner.
  module Detector
    extend RedmineRenderSwitcher::Logger

    # Generation of the detection logic.
    #
    # {CacheKey} mixes this into the formatted-HTML cache key, so any change that
    # can move a verdict MUST bump this constant in the same change set: the
    # pattern tables, the context rules, code-block masking, the threshold
    # comparison, and {Directive::PATTERN}, which decides ahead of all of them.
    # Forgetting to is a defect: old HTML would keep being served for texts whose
    # verdict has changed.
    #
    # The configured threshold is *not* covered here, because it is a setting
    # rather than a change to this code; {CacheKey} puts its current value in the
    # key separately.
    VERSION = 5

    # Redmine's name for the Textile format.
    TEXTILE = "textile"

    # Redmine's name for the Markdown format.
    COMMON_MARK = "common_mark"

    # The outcome of one detection.
    #
    # It carries the verdict and the evidence behind it, and deliberately does not
    # carry the text, so that logging a result can never leak page content.
    #
    # It is a keyword Struct with its writers removed and each instance frozen,
    # rather than a +Data+, because +Data+ arrived in Ruby 3.2 and Redmine 6.0 still
    # supports Ruby 3.1.
    #
    # @!attribute [r] format
    #   @return [String, nil] {TEXTILE}, {COMMON_MARK}, or nil when undecided.
    # @!attribute [r] textile_score
    #   @return [Integer] how much the text looks like Textile.
    # @!attribute [r] markdown_score
    #   @return [Integer] how much the text looks like Markdown.
    # @!attribute [r] reason
    #   @return [Symbol] :directive, :score, :below_threshold or :no_signal.
    Result = Struct.new(:format, :textile_score, :markdown_score, :reason, keyword_init: true) do
      members.each { |member| undef_method(:"#{member}=") }

      # Builds the result from keywords and freezes it.
      #
      # @param attributes [Hash{Symbol => Object}] the four members, by name.
      def initialize(**attributes)
        super
        freeze
      end

      # The result of an explicit directive.
      #
      # A directive is read before any scoring happens, so there is no evidence to
      # carry and both scores are zero. Keeping that here means the invariant is
      # stated once, rather than at each place that has to remember the zeroes.
      #
      # @param format [String] {TEXTILE} or {COMMON_MARK}, as the author named it.
      # @return [Result] the verdict, with no scores behind it.
      def self.directive(format)
        new(format: format, textile_score: 0, markdown_score: 0, reason: :directive)
      end

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

    # Textile inline code, +@like this@+.
    #
    # Both delimiters are kept clear of word characters on the outside, and the
    # content may not begin or end with whitespace. That is what separates real
    # inline code from the two things Redmine writes with the same character: a
    # user mention (+@alice+) and an e-mail address. Without the guards the match
    # runs greedily from one +@+ to the next, so an ordinary Markdown line like
    # "cc @alice and @bob" scored as Textile and cost the page its margin.
    # RedCloth renders neither of those as code, and the detector now agrees.
    TEXTILE_INLINE_CODE = /(?<!\w)@[^@\s](?:[^@\n]*[^@\s])?@(?!\w)/

    # Notation that only Textile gives meaning to, with its weight.
    #
    # A notation earns a place here only when one format renders it as markup and
    # the other leaves it as plain text, or when the two render it differently
    # enough that a reader would notice. Notation both formats render with the same
    # meaning is absent on purpose, even where the HTML tag names differ: getting
    # it wrong changes nothing a reader sees, so moving the score on it buys
    # nothing.
    #
    # Considered and deliberately not scored, so that a later proposal need not
    # repeat the analysis:
    # * +_text_+, +> quote+, +* item+ and +---+, which both formats render alike.
    # * +ABBR(text)+, which matches ordinary prose such as +GET(path)+, and +p. +,
    #   which matches +p. s.+.
    # * Deletion, insertion, span and citation inline markup, footnote markers
    #   (+fn1. +) and Markdown strikethrough (+~~text~~+): too rare to be worth a
    #   pattern, for either format.
    # * Markdown reference links and autolinks.
    # * The +-+ Setext underline, because +---+ is also the horizontal rule that both
    #   formats render alike, and a line of dashes alone does not say which it is.
    # * The plus-sign bullet and the +N) + numbered list, which only Markdown reads
    #   as lists but fall under the same rarity test as the inline notation above.
    TEXTILE_PATTERNS = {
      /^h[1-6]\.\s/ => 5,
      /"[^"\n]+":\S+/ => 4,
      %r{!\S*[./]\S*!} => 3,
      /^bq\.\s/ => 4,
      TEXTILE_INLINE_CODE => 3,
      /^\|_\./ => 5
    }.freeze

    # Notation that only Markdown gives meaning to, with its weight.
    #
    # It follows the same rule as {TEXTILE_PATTERNS}, and the list of notation
    # left out there applies here too. +**bold**+ is the worked example of what the
    # rule keeps out: both formats make it bold, so it says nothing about which one
    # the author wrote.
    #
    # The link pattern steps around an image: +![alt](url)+ contains +[alt](url)+,
    # so without the lookbehind an image would be counted twice and outweigh every
    # other notation in the table for no reason anyone chose.
    MARKDOWN_PATTERNS = {
      /^[ \t]*(?:```|~~~)/ => 5,
      /!\[[^\]\n]*\]\([^)\n]*\)/ => 4,
      /(?<!!)\[[^\]\n]*\]\([^)\n]*\)/ => 4,
      /`[^`\n]+`/ => 3
    }.freeze

    # A line indented by four spaces or a tab.
    #
    # Markdown reads an indented block that follows a blank line as code, and so
    # does Textile, so the detector treats it as a third kind of code block beside
    # fences and +<pre>+. Two spaces are not enough to make code in Markdown, and
    # a rule that guessed at them would misread nested lists.
    INDENTED_LINE = /\A(?: {4}|\t)/

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

    # A line that only Markdown turns into a list item: a dash or a number with a
    # period, then a space.
    #
    # This is the pattern that *scores*, so it is anchored to the start of the line.
    # +* item+ is deliberately absent because both formats read it as a list, and
    # +#+ belongs to {HASH_LINE}. A single such line is not evidence, which is why
    # {.score_list_blocks} asks for two in a row.
    #
    # It looks like {LIST_ITEM_LINE} but is a different piece of knowledge: this
    # one decides what earns points, that one decides what a neighbouring line may
    # be continuing. The two are kept apart on purpose.
    MARKDOWN_LIST_LINE = /\A(?:-|\d+\.)[ \t]/

    # A line that opens a list item, indented or not.
    #
    # It is a context predicate and never earns points. A line that follows one may
    # be a continuation of that item (an indented line, or a +=+ line), not the
    # start of something new. Nested items are indented, so unlike
    # {MARKDOWN_LIST_LINE} this pattern is not anchored to the first column.
    #
    # +#+ is left out on purpose. A +#+ line is as likely a Markdown heading as a
    # Textile list item ({HASH_LINE}), and a heading takes no continuation, so an
    # indented block under one is code. Treating it as a list item would leave the
    # most common shape of an indented code block unmasked.
    LIST_ITEM_LINE = /\A[ \t]*(?:[-*]|\d+\.)[ \t]/

    # A line with nothing on it but whitespace.
    BLANK_LINE = /\A\s*\z/

    # A line of nothing but +=+, which Markdown reads as the underline of a Setext
    # heading.
    #
    # The +-+ underline is left out: +---+ is also the horizontal rule that both
    # formats render alike, so a line of dashes alone says nothing about which one
    # the author wrote.
    SETEXT_UNDERLINE = /\A=+\s*\z/

    # Added to the Markdown score for each block of {MARKDOWN_LIST_LINE} lines.
    #
    # One score per block, not per line, so that the evidence does not grow with the
    # length of the list. Counted per line, a Textile document with a few
    # hand-written dashes would out-score its own headings and flip to Markdown.
    MARKDOWN_LIST_BLOCK_WEIGHT = 3

    # Added to the Markdown score for each Setext heading.
    SETEXT_HEADING_MARKDOWN_WEIGHT = 4

    # A table row: it starts and ends with a pipe.
    #
    # Both ends are required because +| pipe one+ is not a table row in Textile
    # either. The pattern is anchored to the first column, so an indented line, which
    # is code rather than a table, never matches. It ends with +\s*\z+ because the
    # line still carries its newline.
    TABLE_LINE = /\A\|.*\|\s*\z/

    # A row made of nothing but pipes, hyphens, colons and spaces, with at least one
    # hyphen, such as +|---|:--:|+.
    #
    # In a Markdown table it is the row under the header that says which way each
    # column is aligned. Textile has no such row, so its presence turns a table into
    # Markdown evidence. The whole row has to match: a row that only starts like one,
    # such as +| - | x |+, is a Textile row with a dash for a cell.
    #
    # Where the row sits in the table is not checked, so a separator on its own still
    # counts. Anchored to the first column for the same reason as {TABLE_LINE}.
    MARKDOWN_TABLE_SEPARATOR = /\A\|[\s:|-]*-[\s:|-]*\|\s*\z/

    # Added to the Textile score for each table block without a separator row.
    TEXTILE_TABLE_BLOCK_WEIGHT = 4

    # Added to the Markdown score for each table block that has a separator row.
    MARKDOWN_TABLE_BLOCK_WEIGHT = 5

    class << self
      # Detects the format +text+ is written in.
      #
      # @param text [String] the text to inspect. It is never modified.
      # @param threshold [Integer] the score difference the winner must reach.
      # @return [Result] always a result, never nil.
      def detect(text, threshold:)
        masked = mask_code_blocks(text)
        context_textile, context_markdown = context_scores(masked.lines)

        result = build_result(
          score(masked, TEXTILE_PATTERNS) + context_textile,
          score(masked, MARKDOWN_PATTERNS) + context_markdown,
          threshold
        )
        render_switcher_logger.debug { "detected #{result.to_log}" }

        result
      end

      private

      # Blanks out what lives inside a code block, so that a Textile snippet quoted
      # in a Markdown document (or the other way round) cannot sway the verdict.
      #
      # There are three kinds of block: a fenced one, a +<pre>+ one, and an indented
      # one. An indented block opens on an {INDENTED_LINE} that follows a blank line,
      # and runs on through further indented lines and any blank lines among them
      # until a line that is neither. It is never opened while the lines above it
      # lead back to a list item through blank and indented lines alone — blank
      # lines in between or not, one indented continuation paragraph or several —
      # because there the indent continues the item and is not code. A +#+ line is
      # not a list item here, so an indented block under a heading is code. Nothing
      # inside a block is scored, whatever it looks like.
      #
      # The state that decides whether an indent opens a block is tracked from the
      # line as it was written, not from its masked form. A masked line is blank, so
      # tracking that would make a one-line +<pre>+ look like a blank line and open a
      # block on whatever follows it.
      #
      # Fence lines themselves are kept, because a fence is Markdown evidence in its
      # own right. The work happens on a copy; +text+ is left alone (FR-007).
      #
      # @param text [String] the original text.
      # @return [String] a copy with code-block contents replaced by blank lines.
      def mask_code_blocks(text)
        in_fence = false
        in_pre = false
        in_indent = false
        prev_blank = false
        prev_list = false

        text.lines.map do |line|
          fence = FENCE_LINE.match?(line)
          blank = BLANK_LINE.match?(line)
          indented = INDENTED_LINE.match?(line)
          in_indent &&= continues_block?(blank, indented)

          masked =
            if in_fence
              in_fence = false if fence
              fence ? line : "\n"
            elsif in_pre
              in_pre = false if PRE_CLOSE.match?(line)
              "\n"
            elsif in_indent
              "\n"
            elsif fence
              in_fence = true
              line
            elsif PRE_OPEN.match?(line)
              in_pre = true unless PRE_CLOSE.match?(line)
              "\n"
            elsif indented_block_start?(line, prev_blank, prev_list)
              in_indent = true
              "\n"
            else
              line
            end

          prev_list = LIST_ITEM_LINE.match?(line) unless continues_block?(blank, indented)
          prev_blank = blank
          masked
        end.join
      end

      # Tells whether +line+ continues what sits above it instead of starting
      # something new: a blank line or an indented line does. It is the condition
      # for a running indented block to go on, and it is also the condition under
      # which the context of a list item survives: a blank line leaves that
      # context alone and an indented line extends it with a continuation.
      #
      # @param blank [Boolean] whether the line is blank.
      # @param indented [Boolean] whether the line is indented by four spaces or a
      #   tab.
      # @return [Boolean] true when the line carries the block or the list context
      #   above it forward.
      def continues_block?(blank, indented)
        blank || indented
      end

      # Tells whether +line+ opens an indented code block.
      #
      # It must be indented, follow a blank line, and sit outside the context of a
      # list item, whose continuation it would be. Blank lines and indented lines
      # keep that context alive; any other non-blank line ends it.
      #
      # @param line [String] the line, as written.
      # @param prev_blank [Boolean] whether the line above it is blank.
      # @param prev_list [Boolean] whether the text above still sits in the context
      #   of a list item.
      # @return [Boolean] true when a block opens here.
      def indented_block_start?(line, prev_blank, prev_list)
        INDENTED_LINE.match?(line) && prev_blank && !prev_list
      end

      # Adds up one side of the score.
      #
      # @param text [String] the masked text.
      # @param patterns [Hash{Regexp => Integer}] the rule table to apply.
      # @return [Integer] the total score.
      def score(text, patterns)
        patterns.sum { |pattern, weight| text.scan(pattern).size * weight }
      end

      # Adds up what the line-context rules find.
      #
      # Every context rule takes the lines and answers +[textile, markdown]+, so
      # they can be summed pairwise here and a new rule is registered by adding one
      # entry to the list. Each of them looks at how lines sit next to one another,
      # which is what a pattern scanned over the whole text cannot see.
      #
      # @param lines [Array<String>] the lines of the masked text.
      # @return [Array(Integer, Integer)] the Textile and Markdown scores.
      def context_scores(lines)
        [
          score_hash_lines(lines),
          score_list_blocks(lines),
          score_table_blocks(lines),
          score_setext_headings(lines)
        ].transpose.map(&:sum)
      end

      # Scores blocks of dash and numbered list lines for Markdown.
      #
      # Two or more lines in a row make a block, and a block is worth one score
      # however long it is. A single line is no evidence at all: a dash at the start
      # of a line is also how prose breaks off an aside, and a number with a period
      # is how a sentence about a step begins.
      #
      # A blank line does not end a block, because Markdown reads a list with blank
      # lines between its items as one list. Ending the block there would count
      # each item on its own and bring back the length dependence the block score
      # exists to avoid. Anything else that is not a list line ends it.
      #
      # @param lines [Array<String>] the lines of the masked text.
      # @return [Array(Integer, Integer)] the Textile and Markdown scores.
      def score_list_blocks(lines)
        markdown = 0
        run = 0

        # The sentinel is neither blank nor a list line, so it closes a block that
        # runs to the end of the text.
        (lines + [ "end" ]).each do |line|
          if MARKDOWN_LIST_LINE.match?(line)
            run += 1
          elsif !BLANK_LINE.match?(line)
            markdown += MARKDOWN_LIST_BLOCK_WEIGHT if run >= 2
            run = 0
          end
        end

        [ 0, markdown ]
      end

      # Scores blocks of table rows: Markdown when one row is a separator, Textile
      # when none is and there are at least two rows.
      #
      # A table is a run of {TABLE_LINE} rows and each one is scored on its own, so a
      # document may hold a table of each kind. A blank line ends the run, unlike in
      # a list: Markdown ends a table at a blank line, and the next pipe row starts a
      # new one. A lone row with no separator scores nothing, since a single line
      # between pipes is no more evidence than a single dash line is.
      #
      # @param lines [Array<String>] the lines of the masked text.
      # @return [Array(Integer, Integer)] the Textile and Markdown scores.
      def score_table_blocks(lines)
        textile = 0
        markdown = 0
        rows = []

        # The sentinel is not a table row, so it closes a table that runs to the end.
        (lines + [ "" ]).each do |line|
          if TABLE_LINE.match?(line)
            rows << line
            next
          end

          if rows.any? { |row| MARKDOWN_TABLE_SEPARATOR.match?(row) }
            markdown += MARKDOWN_TABLE_BLOCK_WEIGHT
          elsif rows.size >= 2
            textile += TEXTILE_TABLE_BLOCK_WEIGHT
          end
          rows = []
        end

        [ textile, markdown ]
      end

      # Scores Setext headings, a line of text underlined with +=+, for Markdown.
      #
      # Textile has no such heading, so the underline stays as text there. An
      # underline needs a line of text above it to be one: at the start of the text,
      # under a blank line, under a list item or under a +#+ line it is something
      # else (a list item may carry a continuation line, so the +=+ there belongs to
      # the item, and a +#+ line is a heading or a list item already).
      #
      # Each heading scores on its own, not once per block like the other context
      # rules, so a text with several of them gathers evidence for Markdown as it
      # goes. That is accepted, and the reason is in ADR-0005.
      #
      # @param lines [Array<String>] the lines of the masked text.
      # @return [Array(Integer, Integer)] the Textile and Markdown scores.
      def score_setext_headings(lines)
        markdown = 0

        lines.each_cons(2) do |above, line|
          next unless SETEXT_UNDERLINE.match?(line)
          next if [ BLANK_LINE, LIST_ITEM_LINE, HASH_LINE ].any? { |pattern| pattern.match?(above) }

          markdown += SETEXT_HEADING_MARKDOWN_WEIGHT
        end

        [ 0, markdown ]
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
        # A winner always needs a margin of at least one, however low the setting
        # is put: a tie is evidence for neither side, and letting it through would
        # hand the win to whichever side the comparison below happens to test
        # second.
        margin = [ threshold, 1 ].max

        reason =
          if textile.zero? && markdown.zero?
            :no_signal
          elsif (textile - markdown).abs < margin
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
