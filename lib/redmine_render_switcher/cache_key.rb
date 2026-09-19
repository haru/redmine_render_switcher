# frozen_string_literal: true

require_relative "detector"
require_relative "plugin_settings"

module RedmineRenderSwitcher
  # Adds the detector's generation to Redmine's formatted-HTML cache key.
  #
  # This is the plugin's second, and last, coupling point to Redmine core, and it
  # exists because the first one cannot reach here: Redmine's key holds only the
  # format name and a digest of the text
  # (+lib/redmine/wiki_formatting.rb+ +cache_key_for+), and the cache is consulted
  # before any formatter is built. Without this, improving the detector would leave
  # every cached page rendered by the old rules.
  module CacheKey
    # The name this module is recognised by when checking whether it is installed.
    MODULE_NAME = "RedmineRenderSwitcher::CacheKey"

    # Prepends this module to +singleton+, at most once.
    #
    # As with {AutoSwitch.prepend_to}, the guard compares module names, because
    # reloading makes the constant a different object.
    #
    # @param singleton [Class] +Redmine::WikiFormatting.singleton_class+.
    # @return [void]
    def self.prepend_to(singleton)
      return if singleton.ancestors.any? { |mod| mod.name == MODULE_NAME }

      singleton.prepend(self)
    end

    # Returns Redmine's cache key with the detector generation appended.
    #
    # A nil key means Redmine does not want this text cached at all (a new record,
    # for instance). That is an ordinary outcome of building a key, so it is passed
    # straight through rather than papered over. The first half of the key is never
    # rebuilt here; whatever core produced is what gets extended.
    #
    # @param format [String] the format name Redmine is rendering with.
    # @param text [String] the text being rendered.
    # @param object [ActiveRecord::Base, nil] the record the text belongs to.
    # @param attribute [String, Symbol, nil] the attribute holding the text.
    # @return [String, nil] the cache key, or nil when the text is not cacheable.
    def cache_key_for(format, text, object, attribute)
      key = super
      return key if key.nil? || !PluginSettings.auto_detect_enabled?

      "#{key}-rs#{Detector::VERSION}"
    end
  end
end
