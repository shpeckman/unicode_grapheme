# src/unicode_grapheme/utf8.cr

module UW::UTF8
  REPLACEMENT     =   0xFFFD_u32
  MAXIMUM         = 0x10FFFF_u32
  SURROGATE_FIRST =   0xD800_u32
  SURROGATE_LAST  =   0xDFFF_u32

  def self.decode(data : Pointer(UInt8), size : Int32, pos : Int32) : {UInt32, Int32}
    lead = data[pos]
    return {lead.to_u32, pos + 1} if lead < 0x80

    if (lead & 0xE0) == 0xC0
      codepoint = (lead & 0x1F).to_u32
      trailing  = 1
      minimum   = 0x80_u32
    elsif (lead & 0xF0) == 0xE0
      codepoint = (lead & 0x0F).to_u32
      trailing  = 2
      minimum   = 0x800_u32
    elsif (lead & 0xF8) == 0xF0
      codepoint = (lead & 0x07).to_u32
      trailing  = 3
      minimum   = 0x10000_u32
    else
      return {REPLACEMENT, pos + 1}
    end

    return {REPLACEMENT, pos + 1} if pos + trailing >= size

    index = 1
    while index <= trailing
      byte = data[pos + index]
      return {REPLACEMENT, pos + 1} if (byte & 0xC0) != 0x80
      codepoint = (codepoint << 6) | (byte & 0x3F).to_u32
      index += 1
    end

    if codepoint < minimum || codepoint > MAXIMUM ||
       (codepoint >= SURROGATE_FIRST && codepoint <= SURROGATE_LAST)
      return {REPLACEMENT, pos + 1}
    end

    {codepoint, pos + trailing + 1}
  end
end