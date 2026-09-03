# src/unicode_grapheme/cluster_width.cr

struct UW::ClusterWidth
  VARIATION_SELECTOR_16 = 0xFE0F_u32

  def initialize
    @control      = false
    @wide         = false
    @pictographic = false
    @variation    = false
    @regional     = false
  end

  def start(props : Props, codepoint : UInt32) : Nil
    gcb           = props.gcb
    @control      = gcb.control? || gcb.cr? || gcb.lf?
    @wide         = props.wide?
    @pictographic = props.pictographic?
    @variation    = codepoint == VARIATION_SELECTOR_16
    @regional     = gcb.ri?
  end

  def add(props : Props, codepoint : UInt32) : Nil
    @wide ||= props.wide?
    @pictographic ||= props.pictographic?
    @variation ||= codepoint == VARIATION_SELECTOR_16
    @regional ||= props.gcb.ri?
  end

  def value : Int32
    if @control
      0
    elsif @wide || @regional || (@pictographic && @variation)
      2
    else
      1
    end
  end
end
