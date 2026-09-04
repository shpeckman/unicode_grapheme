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

    # Uniform wide-ideograph blocks: every codepoint is GCB=Other,
    # INCB=None, not pictographic, wide => 0x20. Verified against the
    # generated tables.
    if (codepoint >= 0x3400_u32 && codepoint <= 0x4DBF_u32) ||
       (codepoint >= 0x4E00_u32 && codepoint <= 0x9FFF_u32) ||
       (codepoint >= 0xF900_u32 && codepoint <= 0xFAFF_u32)
      return new(0x20_u8)
    end

    pages = Tables::PAGE
    page  = (codepoint >> 8).to_i32
    return new(0_u8) if page >= pages.size

    last = Tables::LO.size - 1
    low  = pages.to_unsafe[page].to_i32
    return new(0_u8) if low > last

    high = page + 1 < pages.size ? pages.to_unsafe[page + 1].to_i32 : last
    high = last if high > last

    lo = Tables::LO.to_unsafe
    hi = Tables::HI.to_unsafe

    while low < high
      mid = (low + high + 1) >> 1
      if lo[mid] <= codepoint
        low = mid
      else
        high = mid - 1
      end
    end

    return new(Tables::V.to_unsafe[low]) if lo[low] <= codepoint && codepoint <= hi[low]

    new(0_u8)
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
