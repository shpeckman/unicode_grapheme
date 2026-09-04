# src/unicode_grapheme.cr

# Usage
# -----
#
#   UW.each("héllo 🇧🇪") do |cluster, width|
#     puts "#{String.new(cluster)} (#{width})"
#   end
#
# Five operations, each with a `String` and a `Bytes` overload:
#
#   UW.each(input) { |cluster : Bytes, width : Int32| }
#   UW.width(input) : Int32
#   UW.count(input) : Int32
#   UW.fit(input, columns) : {Int32, Int32}
#   UW.skip(input, columns) : {Int32, Int32}
#
#   UW.count("e\u0301a\u0301")             # => 2
#   UW.count("\u{1F468}\u200D\u{1F469}")   # => 1
#
#   UW.width("hello")                      # => 5
#   UW.width("\u4E00")                     # => 2
#   UW.width("e\u0301")                    # => 1
#   UW.width("\u{1F1FA}\u{1F1F8}")         # => 2
#   UW.width("\t")                         # => 0

# Fitting to a column budget
# --------------------------
#
# `fit` returns the longest prefix that occupies at most `columns` columns,
# as `{byte_count, width}`. A cluster that would cross the budget is left
# out entirely, so a wide glyph is never cut in half:
#
#   UW.fit("你好世界", 5)                   # => {6, 4}
#
# `skip` is its dual: the shortest prefix occupying at least `columns`
# columns. A cluster straddling the boundary is consumed whole, so the
# returned width may exceed `columns` by one:
#
#   UW.skip("你好世界", 1)                  # => {3, 2}
#
# Together they clip a run of text to a window without splitting clusters
# at either edge.

# ANSI escape sequences
# ---------------------
#
# `UW::ANSI` offers the same five operations with awareness of CSI
# (`ESC [` parameter/intermediate bytes, one final byte) and OSC
# (`ESC ]` payload, closed by BEL or ST) escape sequences. Each sequence
# segments as its own zero-width cluster — atomic for `fit`/`skip`, and a
# hard boundary that never joins the text on either side — so styled text
# measures by its visible cells:
#
#   UW::ANSI.width("\e[31mred\e[0m")   # => 3
#   UW::ANSI.count("\e[31mred\e[0m")   # => 5 (3 letters + 2 escapes)
#   UW::ANSI.fit("\e[31mred\e[0m", 2)  # => {7, 2}
#
# A sequence truncated by the end of the input is consumed whole; a lone
# ESC that introduces no sequence keeps its plain UAX #29 treatment as a
# zero-width control cluster. `UW::Stream` is not ANSI-aware.

# Cluster slices
# --------------
#
# `each` yields `Bytes` views into the original buffer.
# Nothing is copied, so a cluster is only valid for as long as the
# input is.
#
# Materialize with `String.new(cluster)` if you need to keep it:
#
#   clusters = [] of String
#   UW.each(line) { |cluster, _| clusters << String.new(cluster) }

# Width policy
# ------------
#
# Width is computed per cluster, not per codepoint, which is why a flag
# or a family emoji is two columns rather than the sum of its parts.
#
#   Cluster                                             Columns
#   --------------------------------------------------  -------
#   Control, CR, LF                                     0
#   Contains an East Asian Wide or Fullwidth codepoint  2
#   Regional indicator (flag)                           2
#   Extended pictographic followed by U+FE0F            2
#   Everything else                                     1
#
# Combining marks, joiners and variation selectors add nothing on their own,
# so a base character with any number of marks attached stays at the width
# of its base.

# Invalid input
# -------------
#
# `Bytes` input is not assumed to be well-formed UTF-8. Overlong encodings,
# surrogates, out-of-range values and truncated sequences are each treated
# as a single-byte cluster, so iteration always advances and never loops:
#
#   UW.each(Bytes[0xFF, 0x41]) { |cluster, _| p cluster.to_a }
#   # => [255]
#   # => [65]

require "./unicode_grapheme/tables"
require "./unicode_grapheme/props"
require "./unicode_grapheme/utf8"
require "./unicode_grapheme/break_state"
require "./unicode_grapheme/cluster_width"
require "./unicode_grapheme/segmenter"
require "./unicode_grapheme/stream"
require "./unicode_grapheme/ansi"

module UW
  VERSION         = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
  UNICODE_VERSION = "17.0.0"

  def self.each(bytes : Bytes, & : Bytes, Int32 ->) : Nil
    each(Segmenter.new(bytes), bytes) do |cluster, width|
      yield cluster, width
    end
  end

  # :nodoc:
  def self.each(segmenter : Segmenter, bytes : Bytes, & : Bytes, Int32 ->) : Nil
    data = bytes.to_unsafe
    size = bytes.size

    while segmenter.pos < size
      if segmenter.pos == 0 || segmenter.prev.other?
        byte = data[segmenter.pos]
        if byte < 0x80
          start = segmenter.pos
          run   = segmenter.skip_ascii
          run.times { |i| yield bytes[start + i, 1], 1 }
          next if run > 0
        elsif byte >= 0xE3_u8 && byte <= 0xEF_u8
          start = segmenter.pos
          run   = segmenter.skip_cjk
          (run // 3).times { |i| yield bytes[start + i * 3, 3], 2 }
          next if run > 0
        end
      end

      start = segmenter.pos
      length, width = segmenter.next
      break if length == 0
      yield bytes[start, length], width
    end
  end

  def self.each(string : String, & : Bytes, Int32 ->) : Nil
    each(string.to_slice) do |cluster, width|
      yield cluster, width
    end
  end

  def self.width(bytes : Bytes) : Int32
    width(Segmenter.new(bytes), bytes)
  end

  # :nodoc:
  def self.width(segmenter : Segmenter, bytes : Bytes) : Int32
    data  = bytes.to_unsafe
    size  = bytes.size
    total = 0

    while segmenter.pos < size
      if segmenter.pos == 0 || segmenter.prev.other?
        byte = data[segmenter.pos]
        if byte < 0x80
          total += segmenter.skip_ascii
          break if segmenter.pos >= size
        elsif byte >= 0xE3_u8 && byte <= 0xEF_u8
          total += 2 * (segmenter.skip_cjk // 3)
        end
      end

      length, width = segmenter.next
      break if length == 0
      total += width
    end

    total
  end

  def self.width(string : String) : Int32
    width(string.to_slice)
  end

  def self.count(bytes : Bytes) : Int32
    count(Segmenter.new(bytes), bytes)
  end

  # :nodoc:
  def self.count(segmenter : Segmenter, bytes : Bytes) : Int32
    data  = bytes.to_unsafe
    size  = bytes.size
    total = 0

    while segmenter.pos < size
      if segmenter.pos == 0 || segmenter.prev.other?
        byte = data[segmenter.pos]
        if byte < 0x80
          total += segmenter.skip_ascii
          break if segmenter.pos >= size
        elsif byte >= 0xE3_u8 && byte <= 0xEF_u8
          total += segmenter.skip_cjk // 3
        end
      end

      break if segmenter.next[0] == 0
      total += 1
    end

    total
  end

  def self.count(string : String) : Int32
    count(string.to_slice)
  end

  def self.fit(bytes : Bytes, columns : Int32) : {Int32, Int32}
    fit(Segmenter.new(bytes), bytes, columns)
  end

  # :nodoc:
  def self.fit(segmenter : Segmenter, bytes : Bytes, columns : Int32) : {Int32, Int32}
    return {0, 0} if columns <= 0

    size  = bytes.size
    count = 0
    total = 0

    while segmenter.pos < size
      length, width = segmenter.next
      break if length == 0
      break if total + width > columns
      count = segmenter.pos
      total += width
    end

    {count, total}
  end

  def self.fit(string : String, columns : Int32) : {Int32, Int32}
    fit(string.to_slice, columns)
  end

  def self.skip(bytes : Bytes, columns : Int32) : {Int32, Int32}
    skip(Segmenter.new(bytes), bytes, columns)
  end

  # :nodoc:
  def self.skip(segmenter : Segmenter, bytes : Bytes, columns : Int32) : {Int32, Int32}
    return {0, 0} if columns <= 0

    size  = bytes.size
    total = 0

    while segmenter.pos < size && total < columns
      length, width = segmenter.next
      break if length == 0
      total += width
    end

    {segmenter.pos, total}
  end

  def self.skip(string : String, columns : Int32) : {Int32, Int32}
    skip(string.to_slice, columns)
  end
end
