# spec/ansi_spec.cr

require "./spec_helper"

private def ansi_clusters(string : String) : Array(String)
  result = [] of String
  UW::ANSI.each(string) { |bytes, _| result << String.new(bytes) }
  result
end

private def ansi_widths(string : String) : Array(Int32)
  result = [] of Int32
  UW::ANSI.each(string) { |_, width| result << width }
  result
end

describe UW::ANSI do
  describe ".each" do
    it "yields nothing for empty input" do
      called = false
      UW::ANSI.each("") { |_, _| called = true }
      called.should be_false
    end

    it "segments escape-free text exactly like the base each" do
      string = "héllo 🇧🇪 世界 é"
      base   = [] of String
      UW.each(string) { |bytes, _| base << String.new(bytes) }
      ansi_clusters(string).should eq(base)
    end

    it "yields an SGR sequence as its own zero-width cluster" do
      ansi_clusters("\e[31mred\e[0m").should eq(["\e[31m", "r", "e", "d", "\e[0m"])
      ansi_widths("\e[31mred\e[0m").should eq([0, 1, 1, 1, 0])
    end

    it "yields a CSI sequence with parameters and intermediates as one cluster" do
      ansi_clusters("\e[1;2H").should eq(["\e[1;2H"])
      ansi_clusters("\e[?25l").should eq(["\e[?25l"])
      ansi_clusters("\e[!p").should eq(["\e[!p"])
    end

    it "yields a BEL-terminated OSC sequence as one cluster" do
      ansi_clusters("\e]8;;https://example.com\a").should eq(["\e]8;;https://example.com\a"])
    end

    it "yields an ST-terminated OSC sequence as one cluster" do
      ansi_clusters("\e]0;title\e\\").should eq(["\e]0;title\e\\"])
    end

    it "consumes a truncated CSI sequence to the end of the buffer" do
      ansi_clusters("abc\e[31").should eq(["a", "b", "c", "\e[31"])
    end

    it "consumes an unterminated OSC sequence to the end of the buffer" do
      ansi_clusters("\e]8;;http://x").should eq(["\e]8;;http://x"])
    end

    it "ends a malformed CSI sequence before its first invalid byte" do
      ansi_clusters("\e[3\n1m").should eq(["\e[3", "\n", "1", "m"])
    end

    it "ends an OSC sequence before an aborting escape" do
      ansi_clusters("\e]0;t\eX").should eq(["\e]0;t", "\e", "X"])
    end

    it "treats a lone escape as a control cluster" do
      ansi_clusters("\e").should eq(["\e"])
      ansi_widths("\e").should eq([0])
    end

    it "treats an escape introducing no sequence as a control cluster" do
      ansi_clusters("\eXab").should eq(["\e", "X", "a", "b"])
    end

    it "keeps a CRLF pair together between escapes" do
      ansi_clusters("\e[31m\r\n\e[0m").should eq(["\e[31m", "\r\n", "\e[0m"])
    end

    it "is a hard boundary: a ZWJ sequence does not join across an escape" do
      ansi_clusters("\u{1F468}\e[31m\u{200D}\u{1F469}").should eq(["\u{1F468}", "\e[31m", "\u{200D}", "\u{1F469}"])
    end

    it "restarts regional indicator pairing after an escape" do
      ansi_clusters("\u{1F1FA}\u{1F1F8}\e[31m\u{1F1EB}\u{1F1F7}").should eq(["\u{1F1FA}\u{1F1F8}", "\e[31m", "\u{1F1EB}\u{1F1F7}"])
    end

    it "yields byte-slice views into the original buffer" do
      bytes  = "a\e[31mb".to_slice
      slices = [] of Bytes
      UW::ANSI.each(bytes) { |cluster, _| slices << cluster }
      slices.map(&.to_a).should eq([[0x61_u8], "\e[31m".to_slice.to_a, [0x62_u8]])
    end

    it "handles invalid bytes around escapes without looping" do
      slices = [] of Array(UInt8)
      UW::ANSI.each(Bytes[0xFF, 0x1B, 0x5B, 0x6D, 0x41]) { |cluster, _| slices << cluster.to_a }
      slices.should eq([[0xFF_u8], [0x1B_u8, 0x5B_u8, 0x6D_u8], [0x41_u8]])
    end
  end

  describe ".width" do
    it "is zero for empty input" do
      UW::ANSI.width("").should eq(0)
    end

    it "ignores SGR sequences" do
      UW::ANSI.width("\e[31mred\e[0m").should eq(3)
      UW::ANSI.width("\e[1m\e[36mbold cyan\e[0m").should eq(9)
    end

    it "ignores OSC hyperlinks" do
      UW::ANSI.width("\e]8;;https://example.com\aexample\e]8;;\a").should eq(7)
      UW::ANSI.width("\e]8;;https://example.com\e\\example\e]8;;\e\\").should eq(7)
    end

    it "measures styled wide text by visible cells" do
      UW::ANSI.width("\e[1m你\e[0m好").should eq(4)
      UW::ANSI.width("a\e[31m\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}\e[0mb").should eq(4)
    end

    it "does not join a combining mark across an escape" do
      UW::ANSI.width("e\e[31ḿ").should eq(2)
      UW::ANSI.width("é").should eq(1)
    end

    it "equals the base width on escape-free text" do
      ["hello", "你好世界", "éá", "🇺🇸", "\t\n"].each do |string|
        UW::ANSI.width(string).should eq(UW.width(string))
      end
    end
  end

  describe ".count" do
    it "is zero for empty input" do
      UW::ANSI.count("").should eq(0)
    end

    it "counts escape sequences as clusters, consistent with each" do
      UW::ANSI.count("\e[31mred\e[0m").should eq(5)
      UW::ANSI.count("a\e[32mb\e[0m").should eq(4)
    end

    it "equals the base count on escape-free text" do
      ["hello", "你好世界", "éá", "🇺🇸👨‍👩‍👧‍👦"].each do |string|
        UW::ANSI.count(string).should eq(UW.count(string))
      end
    end
  end

  describe ".fit" do
    it "is zero for a non-positive budget" do
      UW::ANSI.fit("\e[31mab", 0).should eq({0, 0})
      UW::ANSI.fit("\e[31mab", -1).should eq({0, 0})
    end

    it "treats escape sequences as free" do
      UW::ANSI.fit("\e[31mab", 1).should eq({6, 1})
    end

    it "includes a trailing sequence when the budget is met" do
      UW::ANSI.fit("ab\e[0m", 2).should eq({6, 2})
    end

    it "excludes a sequence that starts past the budget" do
      UW::ANSI.fit("ab\e[0m", 1).should eq({1, 1})
    end

    it "never splits a sequence" do
      bytes, width = UW::ANSI.fit("a\e[31mb\e[0m", 2)
      {bytes, width}.should eq({11, 2})
      "a\e[31mb\e[0m".byte_slice(0, bytes).should eq("a\e[31mb\e[0m")
    end

    it "clips styled wide text to a window" do
      string = "\e[31m你好世界\e[0m"
      bytes, width = UW::ANSI.fit(string, 5)
      {bytes, width}.should eq({11, 4})
      string.byte_slice(0, bytes).should eq("\e[31m你好")
    end
  end

  describe ".skip" do
    it "is zero for a non-positive budget" do
      UW::ANSI.skip("\e[31mab", 0).should eq({0, 0})
    end

    it "skips escape sequences for free" do
      UW::ANSI.skip("\e[31mab", 1).should eq({6, 1})
    end

    it "consumes a straddling cluster whole" do
      string = "\e[31m你好\e[0m"
      bytes, width = UW::ANSI.skip(string, 1)
      {bytes, width}.should eq({8, 2})
      string.byte_slice(bytes).should eq("好\e[0m")
    end
  end

  describe ".fit and .skip" do
    it "bracket every budget without splitting clusters or escapes" do
      samples = [
        "\e[31m你好\e[0m",
        "a\e[1m你\e[0mb\e[32mc\e[0m",
        "\e]8;;https://example.com\alink\e]8;;\a text",
        "\e[31m\e[0m",
      ]

      samples.each do |string|
        0.upto(UW::ANSI.width(string) + 1) do |budget|
          fit_bytes, fit_width = UW::ANSI.fit(string, budget)
          skip_bytes, skip_width = UW::ANSI.skip(string, budget)

          # Zero-width escapes past the budget point are consumed by fit
          # but not by skip, so only the widths are ordered.
          fit_width.should be <= budget
          fit_width.should be <= skip_width
          fit_bytes.should be <= string.bytesize
          skip_bytes.should be <= string.bytesize

          string.byte_slice(0, fit_bytes).valid_encoding?.should be_true
          string.byte_slice(fit_bytes).valid_encoding?.should be_true
          string.byte_slice(0, skip_bytes).valid_encoding?.should be_true
          string.byte_slice(skip_bytes).valid_encoding?.should be_true
        end
      end
    end
  end

  describe "String and Bytes overloads" do
    string = "a\e[31m你\e[0m\e]8;;u\ab\e]8;;\a"

    it "agree for each" do
      from_bytes = [] of String
      UW::ANSI.each(string.to_slice) { |c, _| from_bytes << String.new(c) }
      ansi_clusters(string).should eq(from_bytes)
    end

    it "agree for width" do
      UW::ANSI.width(string).should eq(UW::ANSI.width(string.to_slice))
    end

    it "agree for count" do
      UW::ANSI.count(string).should eq(UW::ANSI.count(string.to_slice))
    end

    it "agree for fit" do
      UW::ANSI.fit(string, 2).should eq(UW::ANSI.fit(string.to_slice, 2))
    end

    it "agree for skip" do
      UW::ANSI.skip(string, 2).should eq(UW::ANSI.skip(string.to_slice, 2))
    end
  end
end
