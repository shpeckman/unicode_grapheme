# src/unicode_grapheme/segmenter.cr

struct UW::Segmenter
  ASCII_FIRST = 0x20_u8
  ASCII_LAST  = 0x7F_u8

  WORD_BYTES =                      8
  HIGH_BITS  = 0x8080808080808080_u64
  LOW_BITS   = 0x2020202020202020_u64
  DEL_BITS   = 0x7F7F7F7F7F7F7F7F_u64
  ONE_BITS   = 0x0101010101010101_u64

  getter pos : Int32

  def initialize(bytes : Bytes)
    @data            = bytes.to_unsafe
    @size            = bytes.size
    @pos             = 0
    @state           = BreakState.new
    @ahead           = false
    @ahead_pos       = 0
    @ahead_codepoint = 0_u32
    @ahead_props     = Props.new(0_u8)
  end

  def prev : Props::GCB
    @state.prev
  end

  def next : {Int32, Int32}
    return {0, 0} if @pos >= @size

    start = @pos

    if @ahead
      codepoint = @ahead_codepoint
      props     = @ahead_props
      pos       = @ahead_pos
      @ahead    = false
    else
      codepoint, pos = UTF8.decode(@data, @size, @pos)
      props = Props.for(codepoint)
    end

    if props.plain? && pos < @size && ascii_printable?(@data[pos])
      @pos = pos
      @state.reset
      return {pos - start, props.wide? ? 2 : 1}
    end

    width = ClusterWidth.new
    width.start(props, codepoint)
    @state.consume(props)

    while pos < @size
      mark = pos
      codepoint, pos = UTF8.decode(@data, @size, pos)
      following = Props.for(codepoint)

      unless @state.joins?(following)
        @ahead           = true
        @ahead_pos       = pos
        @ahead_codepoint = codepoint
        @ahead_props     = following
        pos              = mark
        break
      end

      width.add(following, codepoint)
      @state.consume(following)
    end

    @pos = pos
    {pos - start, width.value}
  end

  def skip_ascii : Int32
    @ahead = false
    start  = @pos

    while @pos + WORD_BYTES <= @size
      break unless printable_word?(load_word(@pos))
      break unless @pos + WORD_BYTES == @size || ascii_printable?(@data[@pos + WORD_BYTES])
      @pos += WORD_BYTES
    end

    while @pos < @size && ascii_printable?(@data[@pos]) &&
          (@pos + 1 == @size || ascii_printable?(@data[@pos + 1]))
      @pos += 1
    end

    @state.reset
    @pos - start
  end

  private def load_word(offset : Int32) : UInt64
    word = uninitialized UInt64
    pointerof(word).as(UInt8*).copy_from(@data + offset, WORD_BYTES)
    word
  end

  private def printable_word?(word : UInt64) : Bool
    return false if (word & HIGH_BITS) != 0
    return false if ((word &- LOW_BITS) & HIGH_BITS) != 0
    diff = word ^ DEL_BITS
    ((diff &- ONE_BITS) & ~diff & HIGH_BITS) == 0
  end

  private def ascii_printable?(byte : UInt8) : Bool
    byte >= ASCII_FIRST && byte < ASCII_LAST
  end
end
