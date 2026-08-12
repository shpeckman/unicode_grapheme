# src/unicode_grapheme.cr

require "./unicode_grapheme/tables"
require "./unicode_grapheme/props"
require "./unicode_grapheme/utf8"
require "./unicode_grapheme/segmenter"

module UW
  VERSION         = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
  UNICODE_VERSION = "17.0.0"

  def self.each(bytes : Bytes, & : Bytes, Int32 ->) : Nil
    segmenter = Segmenter.new(bytes)

    while true
      start = segmenter.pos
      size, width = segmenter.next
      break if size == 0
      yield bytes[start, size], width
    end
  end

  def self.each(string : String, & : Bytes, Int32 ->) : Nil
    each(string.to_slice) do |cluster, width|
      yield cluster, width
    end
  end

  def self.width(bytes : Bytes) : Int32
    data      = bytes.to_unsafe
    segmenter = Segmenter.new(bytes)
    size      = bytes.size
    total     = 0

    while segmenter.pos < size
      if (segmenter.pos == 0 || segmenter.prev.other?) && data[segmenter.pos] < 0x80
        total += segmenter.skip_ascii
        break if segmenter.pos >= size
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
    data      = bytes.to_unsafe
    segmenter = Segmenter.new(bytes)
    size      = bytes.size
    total     = 0

    while segmenter.pos < size
      if (segmenter.pos == 0 || segmenter.prev.other?) && data[segmenter.pos] < 0x80
        total += segmenter.skip_ascii
        break if segmenter.pos >= size
      end

      break if segmenter.next[0] == 0
      total += 1
    end

    total
  end

  def self.count(string : String) : Int32
    count(string.to_slice)
  end
end