# frozen_string_literal: true

# Namespace for the render switcher plugin: it detects whether a Redmine text is
# written in Textile or Markdown and renders it with the matching formatter,
# whatever +Setting.text_formatting+ says.
module RedmineRenderSwitcher
  # Logging entry point for the plugin.
  #
  # Classes mix this module in and write through {#render_switcher_logger} rather
  # than reaching for +Rails.logger+, so exactly one file knows where the plugin's
  # output goes and how it is tagged.
  module Logger
    # Written in front of every line, so plugin output can be pulled out of a busy
    # Redmine log with a single grep.
    PREFIX = "[redmine_render_switcher]"

    # The sink that plugin code writes to.
    #
    # @return [Module] this module, which responds to +debug+.
    def render_switcher_logger
      RedmineRenderSwitcher::Logger
    end

    class << self
      # Writes one debug line.
      #
      # The message is passed as a block so that nothing is built when the debug
      # level is disabled, which is the normal production case.
      #
      # @yieldreturn [String] the message to write.
      # @return [void]
      def debug
        Rails.logger.debug { "#{PREFIX} #{yield}" }
      end
    end
  end
end
