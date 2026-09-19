# Load the Redmine helper
require_relative "../../../test/test_helper"

# Measure C0 coverage over this plugin's own sources only. Without this filter the
# Redmine core sources loaded by the helper above dominate the denominator and the
# 90% floor stops meaning anything.
#
# The 90% C0 floor is enforced here: a run below it exits non-zero, so CI fails.
#
# The report is written inside the plugin (the CI build copies it out from there) as HTML
# plus a Cobertura coverage.xml for the coverage summary and Codecov.
if defined?(SimpleCov) && ENV["COVERAGE"]
  require "simplecov-cobertura"

  SimpleCov.start do
    add_filter %r{^(?!/?plugins/redmine_render_switcher/lib)}
    coverage_dir File.expand_path("../coverage", __dir__)
    minimum_coverage 90
    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::CoberturaFormatter
    ])
  end
end

# shoulda-context 2.0.0 overrides Rails::TestUnitReporter#format_rerun_snippet with a
# version that calls a bare `executable`. Railties 8.1 moved that to a class-level
# accessor, so the override raises NameError while reporting, and every genuine failure
# is replaced by a crash inside the reporter. Rails' own implementation already handles
# what the override was written to fix, so restore it.
if defined?(Rails::TestUnitReporter)
  Rails::TestUnitReporter.class_eval do
    def format_rerun_snippet(result)
      location, line = if result.respond_to?(:source_location)
                         result.source_location
      else
                         result.method(result.name).source_location
      end

      "#{self.class.executable} #{relative_path_for(location)}:#{line}"
    end
  end
end
