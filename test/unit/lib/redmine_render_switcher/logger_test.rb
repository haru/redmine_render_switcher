# frozen_string_literal: true

require File.expand_path("../../../test_helper", __dir__)

class RedmineRenderSwitcherLoggerTest < ActiveSupport::TestCase
  # Stand-in for the production classes that mix the logger in.
  class Includer
    include RedmineRenderSwitcher::Logger
  end

  context "RedmineRenderSwitcher::Logger" do
    setup do
      @io = StringIO.new
      @original_logger = Rails.logger
      Rails.logger = ActiveSupport::Logger.new(@io)
      @subject = Includer.new
    end

    teardown do
      Rails.logger = @original_logger
    end

    should "write the block result at debug level with the plugin prefix" do
      Rails.logger.level = ::Logger::DEBUG

      @subject.render_switcher_logger.debug { "detected common_mark" }

      assert_includes @io.string, RedmineRenderSwitcher::Logger::PREFIX
      assert_includes @io.string, "detected common_mark"
    end

    should "not evaluate the block when the debug level is disabled" do
      Rails.logger.level = ::Logger::INFO
      evaluated = false

      @subject.render_switcher_logger.debug do
        evaluated = true
        "must not be built"
      end

      assert_not evaluated, "the message block must not be evaluated below debug level"
      assert_equal "", @io.string
    end
  end

  context "plugin sources" do
    should "not call Rails.logger anywhere except in the logger module itself" do
      root = File.expand_path("../../../..", __dir__)
      sources = Dir.glob(File.join(root, "lib", "**", "*.rb")) +
                Dir.glob(File.join(root, "app", "**", "*.rb")) +
                [ File.join(root, "init.rb") ]
      logger_source = File.join(root, "lib", "redmine_render_switcher", "logger.rb")

      offenders = (sources - [ logger_source ]).select do |path|
        File.read(path).include?("Rails.logger")
      end

      assert_equal([], offenders.map { |p| p.sub("#{root}/", "") })
    end
  end
end
