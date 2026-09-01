# src/unicode_grapheme/stream.cr

struct UW::Stream
  def initialize
    @state   = BreakState.new
    @width   = ClusterWidth.new
    @bytes   = 0
    @started = false
  end

  def feed(codepoint : UInt32) : {Int32, Int32}?
    props = Props.for(codepoint)
    size  = UTF8.encoded_length(codepoint)

    unless @started
      start_cluster(props, codepoint, size)
      return nil
    end

    if @state.joins?(props)
      @width.add(props, codepoint)
      @bytes += size
      @state.consume(props)
      return nil
    end

    completed = {@width.value, @bytes}
    start_cluster(props, codepoint, size)
    completed
  end

  def feed(char : Char) : {Int32, Int32}?
    feed(char.ord.to_u32)
  end

  def finish : {Int32, Int32}?
    return nil unless @started

    completed = {@width.value, @bytes}
    reset
    completed
  end

  def reset : Nil
    @state.reset
    @started = false
    @bytes   = 0
  end

  private def start_cluster(props : Props, codepoint : UInt32, size : Int32) : Nil
    @width.start(props, codepoint)
    @bytes   = size
    @started = true
    @state.consume(props)
  end
end
