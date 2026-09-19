# frozen_string_literal: true

module RedmineRenderSwitcher
  # Reads the plugin's own Redmine settings.
  #
  # Every setting key literal lives in this file, and so does the normalisation of
  # the string values that Redmine's settings form stores ("1" / "0" / "5").
  # The declared values in +init.rb+ supply the defaults, so no caller needs a nil
  # fallback of its own.
  module PluginSettings
    # Setting key: whether a text's own content may override the site format.
    AUTO_DETECT_ENABLED_KEY = "auto_detect_enabled"

    # Setting key: how far the two scores must differ before a format is chosen.
    SCORE_THRESHOLD_KEY = "score_threshold"

    class << self
      # Whether auto-detection is switched on.
      #
      # @return [Boolean] true when the plugin may render a text with a formatter
      #   other than the one the site setting names.
      def auto_detect_enabled?
        value = stored[AUTO_DETECT_ENABLED_KEY]
        value == true || value.to_s == "1"
      end

      # The score difference below which the site format is kept.
      #
      # @return [Integer] the configured threshold.
      def score_threshold
        stored[SCORE_THRESHOLD_KEY].to_i
      end

      private

      # @return [Hash] the plugin's stored settings.
      def stored
        Setting.plugin_redmine_render_switcher
      end
    end
  end
end
