srcdir = File.expand_path("../../src", __FILE__)
y2dirs = ENV.fetch("Y2DIR", "").split(":")
ENV["Y2DIR"] = y2dirs.unshift(srcdir).join(":")

# force English locale to avoid failing tests due to translations
# when running in non-English environment
ENV["LC_ALL"] = "en_US.UTF-8"

require "yast"

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
  end

  # track all ruby files under src
  SimpleCov.track_files("#{srcdir}/**/*.rb")

  # use coveralls for on-line code coverage reporting at Travis CI
  if ENV["TRAVIS"]
    require "coveralls"
    SimpleCov.formatters = [
      SimpleCov::Formatter::HTMLFormatter,
      Coveralls::SimpleCov::Formatter
    ]
  end
end
