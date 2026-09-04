# src/unicode_grapheme/ansi.cr

# ANSI-aware variants of the five `UW` operations, for buffers that carry
# CSI and OSC escape sequences alongside the text.
#
# Every escape sequence segments as its own zero-width cluster: it is
# never split (including by `fit` and `skip`), adds nothing to `width`,
# and acts as a hard boundary that never joins the text on either side.
# `count` counts escape sequences like any other cluster, so it stays
# consistent with `each`; use `width` for visible cell counts.
#
#   UW::ANSI.width("\e[1m\e[31merror:\e[0m failed")   # => 14
#
#   UW::ANSI.each("a\e[32mb\e[0m") do |cluster, width|
#     puts "#{String.new(cluster).inspect} (#{width})"
#   end
#   # => "a" (1)
#   # => "\e[32m" (0)
#   # => "b" (1)
#   # => "\e[0m" (0)
#
# Recognized sequences, per ECMA-48:
#
#   CSI   ESC '['  parameter/intermediate bytes (0x20-0x3F)  final byte (0x40-0x7E)
#   OSC   ESC ']'  payload                                   BEL or ST (ESC '\')
#
# A sequence truncated by the end of the input consumes the rest of the
# buffer. A malformed CSI sequence ends just before its first invalid
# byte, and an OSC sequence aborted by a stray ESC ends just before it.
# A lone ESC that introduces neither sequence — including the C1 singles
# — is not special-cased: it keeps its plain UAX #29 treatment as a
# zero-width control cluster.
module UW::ANSI
  def self.each(bytes : Bytes, & : Bytes, Int32 ->) : Nil
    UW.each(Segmenter.new(bytes, ansi: true), bytes) do |cluster, width|
      yield cluster, width
    end
  end

  def self.each(string : String, & : Bytes, Int32 ->) : Nil
    each(string.to_slice) do |cluster, width|
      yield cluster, width
    end
  end

  def self.width(bytes : Bytes) : Int32
    UW.width(Segmenter.new(bytes, ansi: true), bytes)
  end

  def self.width(string : String) : Int32
    width(string.to_slice)
  end

  def self.count(bytes : Bytes) : Int32
    UW.count(Segmenter.new(bytes, ansi: true), bytes)
  end

  def self.count(string : String) : Int32
    count(string.to_slice)
  end

  def self.fit(bytes : Bytes, columns : Int32) : {Int32, Int32}
    UW.fit(Segmenter.new(bytes, ansi: true), bytes, columns)
  end

  def self.fit(string : String, columns : Int32) : {Int32, Int32}
    fit(string.to_slice, columns)
  end

  def self.skip(bytes : Bytes, columns : Int32) : {Int32, Int32}
    UW.skip(Segmenter.new(bytes, ansi: true), bytes, columns)
  end

  def self.skip(string : String, columns : Int32) : {Int32, Int32}
    skip(string.to_slice, columns)
  end
end
