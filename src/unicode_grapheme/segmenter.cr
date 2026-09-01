# src/unicode_grapheme/segmenter.cr

struct UW::Segmenter
  ASCII_FIRST = 0x20_u8
  ASCII_LAST  = 0x7F_u8

  getter pos : Int32

  def initialize(bytes : Bytes)
    @data  = bytes.to_unsafe
    @size  = bytes.size
    @pos   = 0
    @state = BreakState.new
  end

  def prev : Props::GCB
    @state.prev
  end

  def next : {Int32, Int32}
    return {0, 0} if @pos >= @size

    start = @pos
    codepoint, pos = UTF8.decode(@data, @size, @pos)
    props = Props.for(codepoint)

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
        pos = mark
        break
      end

      width.add(following, codepoint)
      @state.consume(following)
    end

    @pos = pos
    {pos - start, width.value}
  end

  def skip_ascii : Int32
    count = 0

    while @pos < @size && ascii_printable?(@data[@pos]) &&
          (@pos + 1 == @size || ascii_printable?(@data[@pos + 1]))
      count += 1
      @pos += 1
    end

    @state.reset
    count
  end

  private def ascii_printable?(byte : UInt8) : Bool
    byte >= ASCII_FIRST && byte < ASCII_LAST
  end
end
