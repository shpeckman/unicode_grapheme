# src/unicode_grapheme/segmenter.cr

struct UW::Segmenter
  VARIATION_SELECTOR_16 = 0xFE0F_u32
  ASCII_FIRST           =    0x20_u8
  ASCII_LAST            =    0x7F_u8

  CONJUNCT_NONE      = 0_u8
  CONJUNCT_CONSONANT = 1_u8
  CONJUNCT_LINKED    = 2_u8

  getter pos  : Int32
  getter prev : Props::GCB

  def initialize(bytes : Bytes)
    @data             = bytes.to_unsafe
    @size             = bytes.size
    @pos              = 0
    @prev             = Props::GCB::Other
    @regional_run     = 0
    @pictographic_run = false
    @conjunct         = CONJUNCT_NONE
  end

  def next : {Int32, Int32}
    return {0, 0} if @pos >= @size

    start = @pos
    codepoint, pos = UTF8.decode(@data, @size, @pos)
    props = Props.for(codepoint)

    if props.plain? && pos < @size && ascii_printable?(@data[pos])
      @pos = pos
      reset
      return {pos - start, props.wide? ? 2 : 1}
    end

    gcb          = props.gcb
    control      = gcb.control? || gcb.cr? || gcb.lf?
    wide         = props.wide?
    pictographic = props.pictographic?
    variation    = codepoint == VARIATION_SELECTOR_16
    regional     = gcb.ri?
    consume(props)

    while pos < @size
      mark = pos
      codepoint, pos = UTF8.decode(@data, @size, pos)
      following = Props.for(codepoint)

      unless joins?(following)
        pos = mark
        break
      end

      wide ||= following.wide?
      pictographic ||= following.pictographic?
      variation ||= codepoint == VARIATION_SELECTOR_16
      regional ||= following.gcb.ri?
      consume(following)
    end

    @pos = pos
    width = if control
              0
            elsif wide || regional || (pictographic && variation)
              2
            else
              1
            end

    {pos - start, width}
  end

  def skip_ascii : Int32
    count = 0

    while @pos < @size && ascii_printable?(@data[@pos]) &&
          (@pos + 1 == @size || ascii_printable?(@data[@pos + 1]))
      count += 1
      @pos += 1
    end

    reset
    count
  end

  private def ascii_printable?(byte : UInt8) : Bool
    byte >= ASCII_FIRST && byte < ASCII_LAST
  end

  private def reset : Nil
    @regional_run     = 0
    @pictographic_run = false
    @conjunct         = CONJUNCT_NONE
    @prev             = Props::GCB::Other
  end

  private def consume(props : Props) : Nil
    if props.plain?
      reset
      return
    end

    gcb           = props.gcb
    @regional_run = gcb.ri? ? @regional_run + 1 : 0

    if props.pictographic?
      @pictographic_run = true
    elsif !gcb.extend? && !gcb.zwj?
      @pictographic_run = false
    end

    incb = props.incb
    incb = Props::INCB::Extend if incb.none? && (gcb.extend? || gcb.zwj?)

    case incb
    when .consonant?
      @conjunct = CONJUNCT_CONSONANT
    when .linker?
      @conjunct = CONJUNCT_LINKED if @conjunct >= CONJUNCT_CONSONANT
    when .extend?
    else
      @conjunct = CONJUNCT_NONE
    end

    @prev = gcb
  end

  private def joins?(following : Props) : Bool
    previous = @prev
    gcb      = following.gcb

    if previous.other? && gcb.other? &&
       (!following.incb.consonant? || @conjunct != CONJUNCT_LINKED)
      return false
    end

    return true if (gcb.extend? || gcb.zwj?) && previous > Props::GCB::Control
    return true if previous.cr? && gcb.lf?

    if previous.control? || previous.cr? || previous.lf? ||
       gcb.control? || gcb.cr? || gcb.lf?
      return false
    end

    return true if previous.l? && (gcb.l? || gcb.v? || gcb.lv? || gcb.lvt?)
    return true if (previous.lv? || previous.v?) && (gcb.v? || gcb.t?)
    return true if (previous.lvt? || previous.t?) && gcb.t?
    return true if gcb.extend? || gcb.zwj?
    return true if gcb.spacing_mark?
    return true if previous.prepend?
    return true if @conjunct == CONJUNCT_LINKED && following.incb.consonant?
    return true if previous.zwj? && @pictographic_run && following.pictographic?
    return true if previous.ri? && gcb.ri? && @regional_run.odd?

    false
  end
end
