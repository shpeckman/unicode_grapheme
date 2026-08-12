# spec/spec_helper.cr

require "spec"
require "http/client"
require "file_utils"
require "../src/unicode_grapheme"

module SpecHelper
  extend self

  CACHE_DIR = File.join(__DIR__, "fixtures")

  GRAPHEME_BREAK_TEST_URL =
    "https://www.unicode.org/Public/#{UW::UNICODE_VERSION}/ucd/auxiliary/GraphemeBreakTest.txt"

  BREAK    = '\u00F7'
  NO_BREAK = '\u00D7'

  record BreakCase,
    line        : Int32,
    clusters    : Array(String),
    description : String do
    def source : String
      clusters.join
    end
  end

  def fixture(name : String, url : String) : String
    FileUtils.mkdir_p(CACHE_DIR)
    path = File.join(CACHE_DIR, name)
    return File.read(path) if File.exists?(path)

    body = HTTP::Client.get(url) do |response|
      raise "failed to fetch #{url}: #{response.status_code}" unless response.success?
      response.body_io.gets_to_end
    end

    File.write(path, body)
    body
  end

  def break_cases : Array(BreakCase)
    parse_break_test(fixture("GraphemeBreakTest.txt", GRAPHEME_BREAK_TEST_URL))
  end

  def parse_break_test(data : String) : Array(BreakCase)
    cases = [] of BreakCase

    data.each_line.with_index(1) do |raw, number|
      body, _, comment = raw.partition('#')
      body = body.strip
      next if body.empty?

      clusters = [] of String
      builder  = String::Builder.new
      pending  = false

      body.split(' ') do |token|
        token = token.strip
        next if token.empty?

        case token
        when BREAK.to_s
          clusters << builder.to_s if pending
          builder = String::Builder.new
          pending = false
        when NO_BREAK.to_s
        else
          builder << token.to_i(16).chr
          pending = true
        end
      end

      cases << BreakCase.new(number, clusters, comment.strip)
    end

    cases
  end
end
