# frozen_string_literal: true

require_relative "detector"
require_relative "directive"
require_relative "logger"
require_relative "plugin_settings"

module RedmineRenderSwitcher
  # Prepended to both of Redmine's formatters, so that a text written in the
  # format the site setting does not name is still rendered the way its author
  # wrote it.
  #
  # This module is the plugin's whole coupling surface to Redmine's rendering. It
  # defines only the five methods of the formatter contract and touches no
  # formatter internals, so a Redmine upgrade can only break it in one place.
  #
  # When detection is inconclusive the module calls +super+, rendering with the
  # formatter the site setting already chose. That is the designed outcome of a
  # successful decision, not an error being swallowed, and it is never written as
  # a rescue.
  module AutoSwitch
    include RedmineRenderSwitcher::Logger

    # Thread-local flag raised while a delegated call is in flight.
    #
    # The formatter being delegated to carries this same module, so without the
    # flag the two would hand the text back and forth forever.
    REENTRANCY_KEY = :redmine_render_switcher_switching

    # The formatter classes this module may be prepended to, and the Redmine
    # format name each of them renders. A class that is not listed is left alone.
    FORMAT_BY_FORMATTER = {
      "Redmine::WikiFormatting::Textile::Formatter" => Detector::TEXTILE,
      "Redmine::WikiFormatting::CommonMark::Formatter" => Detector::COMMON_MARK
    }.freeze

    # The name this module is recognised by when checking whether it is installed.
    MODULE_NAME = "RedmineRenderSwitcher::AutoSwitch"

    # Prepends this module to +klass+, at most once.
    #
    # The guard compares module *names* rather than identity: Rails reloading
    # rebuilds the constant as a different object, so +ancestors.include?(self)+
    # would miss an earlier copy and stack a second one on top.
    #
    # @param klass [Class] the formatter class to patch.
    # @return [void]
    def self.prepend_to(klass)
      return if klass.ancestors.any? { |mod| mod.name == MODULE_NAME }

      klass.prepend(self)
    end

    # Keeps the text and options so that a delegate can be built from them later.
    #
    # Detection deliberately does not happen here: a formatter is built for every
    # text Redmine considers rendering, and paying for detection on instances that
    # are never rendered would be pure waste.
    #
    # @param text [String] the text to render.
    # @param options [Hash] the formatter options Redmine passes through.
    def initialize(text, options = {})
      @render_switcher_text = text
      @render_switcher_options = options
      super
    end

    # Renders the text, using the other formatter when the content calls for it.
    #
    # @param args [Array] the arguments Redmine passes to the formatter.
    # @return [String] the rendered HTML.
    def to_html(*args)
      delegate = render_switcher_delegate
      return super unless delegate

      render_switcher_switching { delegate.to_html(*args) }
    end

    # Splits the text into the part before, the part inside and the part after the
    # requested section.
    #
    # @param index [Integer] the 1-based section number.
    # @return [Array<String>] the three parts.
    def extract_sections(index)
      delegate = render_switcher_delegate
      return super unless delegate

      render_switcher_switching { delegate.extract_sections(index) }
    end

    # Returns one section of the text together with its digest.
    #
    # @param index [Integer] the 1-based section number.
    # @return [Array(String, String)] the section and its hash.
    def get_section(index)
      delegate = render_switcher_delegate
      return super unless delegate

      render_switcher_switching { delegate.get_section(index) }
    end

    # Rebuilds the text with one section replaced.
    #
    # The text handed in is never modified in place, and nothing outside the
    # replaced section is rewritten, so a directive line on the first line of the
    # body survives any number of section saves.
    #
    # @param index [Integer] the 1-based section number.
    # @param update [String] the new content of that section.
    # @param hash [String, nil] the digest the caller last saw, for stale detection.
    # @return [String] the rebuilt text.
    def update_section(index, update, hash = nil)
      delegate = render_switcher_delegate
      return super unless delegate

      render_switcher_switching { delegate.update_section(index, update, hash) }
    end

    private

    # The formatter to hand this text to, or nil to render it here.
    #
    # Memoised per instance so that every method of the contract works off one
    # verdict and one delegate. Section-edit links are numbered from the headings
    # in the rendered HTML while +get_section+ numbers them from the source, so
    # the two must not be allowed to disagree about the format.
    #
    # @return [Object, nil] the delegate formatter, or nil.
    def render_switcher_delegate
      return @render_switcher_delegate if defined?(@render_switcher_delegate)

      @render_switcher_delegate = build_render_switcher_delegate
    end

    # Applies the delegation conditions in order and builds the delegate.
    #
    # @return [Object, nil] the delegate formatter, or nil when this formatter
    #   should render the text itself.
    def build_render_switcher_delegate
      return nil unless PluginSettings.auto_detect_enabled?
      return nil if Thread.current[REENTRANCY_KEY]

      own_format = FORMAT_BY_FORMATTER[self.class.name]
      return nil unless own_format

      format = render_switcher_detection.format
      return nil if format.nil? || format == own_format

      render_switcher_switching do
        Redmine::WikiFormatting.formatter_for(format).new(@render_switcher_text, @render_switcher_options)
      end
    end

    # The detection result for this instance, computed at most once.
    #
    # @return [Detector::Result] the verdict and the scores behind it.
    def render_switcher_detection
      @render_switcher_detection ||= build_render_switcher_detection
    end

    # Decides the format, giving the explicit directive the first and final word.
    #
    # The directive is evaluated ahead of every scoring rule (FR-013), and when it
    # answers, the detector is not run at all. Both scores are therefore zero on a
    # :directive result, which is the invariant the data model states.
    #
    # @return [Detector::Result] the verdict and the scores behind it.
    def build_render_switcher_detection
      directive = Directive.parse(@render_switcher_text)
      if directive
        result = Detector::Result.directive(directive)
        render_switcher_logger.debug { "detected #{result.to_log}" }
        return result
      end

      Detector.detect(@render_switcher_text, threshold: PluginSettings.score_threshold)
    end

    # Runs the block with the re-entrancy flag raised.
    #
    # The previous value is restored rather than cleared, so that nesting a
    # delegate construction inside a delegated call cannot drop the outer guard.
    #
    # @yield the work to do while delegating.
    # @return [Object] whatever the block returns.
    def render_switcher_switching
      previous = Thread.current[REENTRANCY_KEY]
      Thread.current[REENTRANCY_KEY] = true
      yield
    ensure
      Thread.current[REENTRANCY_KEY] = previous
    end
  end
end
