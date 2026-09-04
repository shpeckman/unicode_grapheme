# src/unicode_grapheme/break_state.cr

struct UW::BreakState
  CONJUNCT_NONE      = 0_u8
  CONJUNCT_CONSONANT = 1_u8
  CONJUNCT_LINKED    = 2_u8

  BREAK = 0_u8
  JOIN  = 1_u8
  CHECK = 2_u8

  GCB_COUNT = 14

  TRANSITION = Slice(UInt8).literal(
    2_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    2_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    2_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    2_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 2_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    1_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 1_u8, 1_u8, 1_u8, 1_u8, 1_u8, 1_u8, 1_u8, 1_u8,
    2_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 0_u8, 0_u8, 0_u8,
    2_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8, 1_u8, 1_u8, 1_u8, 0_u8, 1_u8, 1_u8,
    2_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8, 1_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8,
    2_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8,
    2_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8, 1_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8,
    2_u8, 0_u8, 0_u8, 0_u8, 1_u8, 1_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8, 1_u8, 0_u8, 0_u8,
  )

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
    index  = @prev.value.to_i32 * GCB_COUNT + following.gcb.value.to_i32
    result = TRANSITION.to_unsafe[index]

    return true if result == JOIN
    return false if result == BREAK

    conditional?(following)
  end

  private def conditional?(following : Props) : Bool
    return true if @conjunct == CONJUNCT_LINKED && following.incb.consonant?
    return true if @prev.zwj? && @pictographic_run && following.pictographic?
    return true if @prev.ri? && @regional_run.odd?

    false
  end
end
