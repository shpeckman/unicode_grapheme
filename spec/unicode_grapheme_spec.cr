# spec/unicode_grapheme_spec.cr

require "./spec_helper"

private def clusters(string : String) : Array(String)
  result = [] of String
  UW.each(string) do |bytes, _width|
    result << String.new(bytes)
  end
  result
end

private def widths(string : String) : Array(Int32)
  result = [] of Int32
  UW.each(string) do |_bytes, width|
    result << width
  end
  result
end

describe UW do
  describe "UAX #29 GraphemeBreakTest" do
    it "segments every official test case" do
      failures = [] of String

      SpecHelper.break_cases.each do |test|
        actual = clusters(test.source)
        next if actual == test.clusters

        failures << "line #{test.line}: expected #{test.clusters.inspect}, " \
                    "got #{actual.inspect} (#{test.description})"
      end

      unless failures.empty?
        shown = failures.first(20).join('\n')
        fail "#{failures.size} grapheme break failures:\n#{shown}"
      end
    end

    it "counts clusters consistently with each" do
      SpecHelper.break_cases.each do |test|
        UW.count(test.source).should eq(test.clusters.size)
      end
    end
  end

  describe ".each" do
    it "yields nothing for empty input" do
      clusters("").should be_empty
    end

    it "yields each ASCII byte as its own cluster" do
      clusters("hello").should eq(["h", "e", "l", "l", "o"])
    end

    it "keeps a CRLF pair together" do
      clusters("a\r\nb").should eq(["a", "\r\n", "b"])
    end

    it "splits a lone CR from a following LF-less byte" do
      clusters("\ra").should eq(["\r", "a"])
    end

    it "attaches a combining mark to its base" do
      clusters("e\u0301").should eq(["e\u0301"])
    end

    it "keeps a Hangul LVT syllable together" do
      clusters("\u1100\u1161\u11A8").should eq(["\u1100\u1161\u11A8"])
    end

    it "keeps an emoji ZWJ sequence together" do
      family = "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}"
      clusters(family).should eq([family])
    end

    it "pairs regional indicators into flags" do
      clusters("\u{1F1FA}\u{1F1F8}\u{1F1EB}\u{1F1F7}").should eq([
        "\u{1F1FA}\u{1F1F8}",
        "\u{1F1EB}\u{1F1F7}",
      ])
    end

    it "keeps an emoji with a skin-tone modifier together" do
      clusters("\u{1F44D}\u{1F3FB}").should eq(["\u{1F44D}\u{1F3FB}"])
    end

    it "joins an Indic consonant conjunct across a linker" do
      conjunct = "\u0915\u094D\u0915"
      clusters(conjunct).should eq([conjunct])
    end

    it "yields byte-slice views into the original buffer" do
      bytes  = "abc".to_slice
      slices = [] of Bytes
      UW.each(bytes) { |cluster, _| slices << cluster }
      slices.map(&.to_a).should eq([[97_u8], [98_u8], [99_u8]])
    end

    it "yields an invalid lead byte as its own cluster without looping" do
      slices = [] of Array(UInt8)
      UW.each(Bytes[0xFF, 0x41]) { |cluster, _| slices << cluster.to_a }
      slices.should eq([[0xFF_u8], [0x41_u8]])
    end
  end

  describe ".width" do
    it "is zero for empty input" do
      UW.width("").should eq(0)
    end

    it "counts one column per ASCII character" do
      UW.width("hello").should eq(5)
    end

    it "counts two columns for a wide CJK character" do
      UW.width("\u4E00").should eq(2)
    end

    it "counts two columns for an emoji cluster" do
      UW.width("\u{1F600}").should eq(2)
    end

    it "counts two columns for a flag" do
      UW.width("\u{1F1FA}\u{1F1F8}").should eq(2)
    end

    it "gives a combining mark no extra width" do
      UW.width("e\u0301").should eq(1)
    end

    it "treats a variation-selector-16 sequence as wide" do
      UW.width("\u2764\uFE0F").should eq(2)
    end

    it "gives zero width to a control character" do
      UW.width("\t").should eq(0)
    end

    it "sums a mixed run" do
      UW.width("a\u4E00\u{1F600}b").should eq(6)
    end

    it "matches the per-cluster width sum on every test case" do
      SpecHelper.break_cases.each do |test|
        UW.width(test.source).should eq(widths(test.source).sum)
      end
    end
  end

  describe ".count" do
    it "is zero for empty input" do
      UW.count("").should eq(0)
    end

    it "counts combining sequences as single clusters" do
      UW.count("e\u0301a\u0301").should eq(2)
    end
  end

  describe ".fit" do
    it "is zero for empty input" do
      UW.fit("", 3).should eq({0, 0})
    end

    it "is zero for a non-positive budget" do
      UW.fit("abc", 0).should eq({0, 0})
      UW.fit("abc", -2).should eq({0, 0})
    end

    it "fits the whole input when the budget allows" do
      UW.fit("abc", 10).should eq({3, 3})
    end

    it "fits an exact budget" do
      UW.fit("你好", 4).should eq({6, 4})
    end

    it "leaves out a wide cluster that would cross the budget" do
      UW.fit("你ab", 1).should eq({0, 0})
      UW.fit("a你b", 2).should eq({1, 1})
    end

    it "never splits a combining sequence" do
      UW.fit("e\u0301a", 1).should eq({3, 1})
    end

    it "never splits a flag" do
      UW.fit("\u{1F1FA}\u{1F1F8}ab", 1).should eq({0, 0})
      UW.fit("\u{1F1FA}\u{1F1F8}ab", 2).should eq({8, 2})
    end

    it "counts zero-width controls as free" do
      UW.fit("\ta", 1).should eq({2, 1})
    end

    it "matches the documented example" do
      UW.fit("你好世界", 5).should eq({6, 4})
    end
  end

  describe ".skip" do
    it "is zero for empty input" do
      UW.skip("", 3).should eq({0, 0})
    end

    it "is zero for a non-positive budget" do
      UW.skip("abc", 0).should eq({0, 0})
      UW.skip("abc", -2).should eq({0, 0})
    end

    it "returns the whole input when the budget exceeds its width" do
      UW.skip("ab", 10).should eq({2, 2})
    end

    it "consumes a straddling cluster whole" do
      UW.skip("a你b", 2).should eq({4, 3})
    end

    it "stops once the budget is reached" do
      UW.skip("你好", 3).should eq({6, 4})
    end

    it "skips zero-width controls" do
      UW.skip("\ta", 1).should eq({2, 1})
    end

    it "matches the documented example" do
      UW.skip("你好世界", 1).should eq({3, 2})
    end
  end

  describe ".fit and .skip" do
    it "bracket every budget without splitting clusters" do
      samples = [
        "你好世界",
        "a你b\u{1F600}c",
        "e\u0301\u{1F1FA}\u{1F1F8}x",
        "\t\tab",
        "hello",
      ]

      samples.each do |string|
        0.upto(UW.width(string) + 1) do |budget|
          fit_bytes, fit_width = UW.fit(string, budget)
          skip_bytes, skip_width = UW.skip(string, budget)

          fit_bytes.should be <= skip_bytes
          fit_width.should be <= skip_width
          skip_bytes.should be <= string.bytesize

          unless fit_bytes == string.bytesize
            remainder = string.byte_slice(fit_bytes)
            remainder.valid_encoding?.should be_true
          end
        end
      end
    end
  end

  describe "String and Bytes overloads" do
    it "agree for each" do
      string      = "a\u4E00\u{1F1FA}\u{1F1F8}e\u0301"
      from_string = clusters(string)
      from_bytes  = [] of String
      UW.each(string.to_slice) { |c, _| from_bytes << String.new(c) }
      from_bytes.should eq(from_string)
    end

    it "agree for width" do
      string = "a\u4E00\u{1F1FA}\u{1F1F8}"
      UW.width(string).should eq(UW.width(string.to_slice))
    end

    it "agree for count" do
      string = "a\u4E00\u{1F1FA}\u{1F1F8}"
      UW.count(string).should eq(UW.count(string.to_slice))
    end

    it "agree for fit" do
      string = "a\u4E00\u{1F1FA}\u{1F1F8}"
      UW.fit(string, 3).should eq(UW.fit(string.to_slice, 3))
    end

    it "agree for skip" do
      string = "a\u4E00\u{1F1FA}\u{1F1F8}"
      UW.skip(string, 3).should eq(UW.skip(string.to_slice, 3))
    end
  end

  describe UW::Stream do
    it "returns nil while a cluster is still open" do
      stream = UW::Stream.new
      stream.feed('e').should be_nil
      stream.feed('\u0301').should be_nil
    end

    it "returns the completed cluster's width and byte length on a break" do
      stream = UW::Stream.new
      stream.feed('e')
      stream.feed('\u0301')
      stream.feed('a').should eq({1, "e\u0301".bytesize})
    end

    it "flushes the pending cluster with finish" do
      stream = UW::Stream.new
      stream.feed('\u4E00')
      stream.finish.should eq({2, 3})
      stream.finish.should be_nil
    end

    it "reports zero width for a control cluster" do
      stream = UW::Stream.new
      stream.feed('\t')
      stream.feed('a').should eq({0, 1})
    end

    it "drops pending state on reset" do
      stream = UW::Stream.new
      stream.feed('\u{1F1FA}')
      stream.reset
      stream.finish.should be_nil
      stream.feed('\u{1F1F8}').should be_nil
      stream.finish.should eq({2, 4})
    end

    it "accepts raw codepoints" do
      stream = UW::Stream.new
      stream.feed(0x1F600_u32)
      stream.finish.should eq({2, 4})
    end

    it "matches the batch API on every official test case" do
      failures = [] of String

      SpecHelper.break_cases.each do |test|
        next unless test.source.valid_encoding?

        stream = UW::Stream.new
        actual = [] of {String, Int32}
        offset = 0
        bytes  = test.source.to_slice

        test.source.each_char do |char|
          next unless completed = stream.feed(char)
          width, size = completed
          actual << {String.new(bytes[offset, size]), width}
          offset += size
        end

        if completed = stream.finish
          width, size = completed
          actual << {String.new(bytes[offset, size]), width}
          offset += size
        end

        if offset != test.source.bytesize
          fail "offset #{offset} != #{test.source.bytesize} at line #{test.line}: #{test.source.bytes.inspect}"
        end

        expected = [] of {String, Int32}
        UW.each(test.source) { |cluster, width| expected << {String.new(cluster), width} }

        next if actual == expected
        failures << "line #{test.line}: expected #{expected.inspect}, " \
                    "got #{actual.inspect} (#{test.description})"
      end

      unless failures.empty?
        shown = failures.first(20).join('\n')
        fail "#{failures.size} streaming failures:\n#{shown}"
      end
    end
  end
  describe "run fast paths" do
    it "attaches a combining mark after a CJK run" do
      clusters("中中́").should eq(["中", "中́"])
      UW.width("中中́").should eq(4)
      UW.count("中中́").should eq(2)
    end

    it "attaches a combining mark after an ASCII run" do
      clusters("abcdef́").should eq(["a", "b", "c", "d", "e", "f́"])
    end

    it "segments a Hangul run but joins a trailing jamo" do
      clusters("가각ᆨ").should eq(["가", "각ᆨ"])
      UW.width("가각ᆨ").should eq(4)
    end

    it "does not steal a run start after a Prepend" do
      clusters("؀中中").should eq(["؀中", "中"])
    end

    it "segments long runs of ideographs and syllables" do
      text = "中" * 40 + "가" * 40
      UW.count(text).should eq(80)
      UW.width(text).should eq(160)
      clusters(text).size.should eq(80)
    end

    it "fits a budget inside a wide run without splitting a cluster" do
      UW.fit("中中中中", 3).should eq({3, 2})
      UW.fit("中中中中", 5).should eq({6, 4})
    end

    it "fits a budget inside an ASCII run" do
      UW.fit("hello world", 4).should eq({4, 4})
    end

    it "keeps zero-width clusters when the budget is met exactly" do
      UW.fit("helló", 5).should eq({7, 5})
      UW.fit("helló", 4).should eq({4, 4})
    end

    it "skips into a wide run, consuming a straddling cluster whole" do
      UW.skip("中中中", 1).should eq({3, 2})
      UW.skip("中中中", 3).should eq({6, 4})
      UW.skip("中中中", 6).should eq({9, 6})
    end

    it "skips a Hangul run" do
      UW.skip("가각간", 3).should eq({6, 4})
    end

    it "measures a long mixed line consistently across operations" do
      line  = "hello 世界 가각 \u{1F600} x" * 30
      total = 0
      count = 0
      UW.each(line) { |_c, w| total += w; count += 1 }
      UW.width(line).should eq(total)
      UW.count(line).should eq(count)
      UW.fit(line, total).should eq({line.bytesize, total})
    end
  end
end
