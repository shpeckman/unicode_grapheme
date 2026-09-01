# src/unicode_grapheme/break_state.cr

struct UW::BreakState
  CONJUNCT_NONE      = 0_u8
  CONJUNCT_CONSONANT = 1_u8
  CONJUNCT_LINKED    = 2_u8

  getter prev : Props::GCB

  def initialize
    @prev             = Props::GCB::Other
    @regional_run     = 0
    @pictographic_run = false
    @conjunct         = CONJUNCT_NONE
  end

  def reset : Nil
    @regional_run     = 0
    @pictographic_run = false
    @conjunct         = CONJUNCT_NONE
    @prev             = Props::GCB::Other
  end

  def consume(props : Props) : Nil
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

  def joins?(following : Props) : Bool
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
