# src/unicode_grapheme/props.cr

struct UW::Props
  enum GCB : UInt8
    Other
    CR
    LF
    Control
    Extend
    ZWJ
    RI
    Prepend
    SpacingMark
    L
    V
    T
    LV
    LVT
  end

  enum INCB : UInt8
    None
    Consonant
    Linker
    Extend
  end

  HANGUL_FIRST = 0xAC00_u32
  HANGUL_LAST  = 0xD7A3_u32
  HANGUL_CYCLE =     28_u32
  HANGUL_LV    =    0x2C_u8
  HANGUL_LVT   =    0x2D_u8

  MAXIMUM       = 0x10FFFF_u32
  UNIFORM_BIT   =   0x8000_u16
  UNIFORM_VALUE =     0xFF_u16

  GCB_MASK          = 0x0F_u8
  PICTOGRAPHIC_MASK = 0x10_u8
  WIDE_MASK         = 0x20_u8
  INCB_SHIFT        =       6
  INCB_MASK         = 0x03_u8
  PLAIN_MASK        = 0xDF_u8

  getter value : UInt8

  def initialize(@value : UInt8)
  end

  def self.for(codepoint : UInt32) : Props
    return new(Tables::ASCII.to_unsafe[codepoint]) if codepoint < 0x80_u32

    if codepoint >= HANGUL_FIRST && codepoint <= HANGUL_LAST
      return new((codepoint - HANGUL_FIRST) % HANGUL_CYCLE == 0 ? HANGUL_LV : HANGUL_LVT)
    end

    # Two-level flat lookup, one entry per 256-codepoint page. A page
    # whose codepoints all share one value stores it inline as
    # UNIFORM_BIT | value; any other page indexes a dense 256-entry
    # block. Either way the lookup is two loads and no search.
    return new(0_u8) if codepoint > MAXIMUM

    entry = Tables::PAGE.to_unsafe[(codepoint >> 8).to_i32]
    return new((entry & UNIFORM_VALUE).to_u8) if entry.bits_set?(UNIFORM_BIT)

    new(Tables::BLOCK.to_unsafe[(entry.to_i32 << 8) | (codepoint & 0xFF_u32).to_i32])
  end

  def gcb : GCB
    GCB.new(@value & GCB_MASK)
  end

  def incb : INCB
    INCB.new((@value >> INCB_SHIFT) & INCB_MASK)
  end

  def pictographic? : Bool
    @value.bits_set?(PICTOGRAPHIC_MASK)
  end

  def wide? : Bool
    @value.bits_set?(WIDE_MASK)
  end

  def plain? : Bool
    (@value & PLAIN_MASK) == 0
  end
end
