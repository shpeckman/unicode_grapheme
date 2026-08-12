# src/unicode_grapheme/tables.cr

module UW::Tables
  macro build_from_file(type, prefix, suffix, filename)
    Slice({{type}}).literal(
      {% for w in read_file("#{__DIR__}/#{filename.id}").gsub(/\n/, " ").split(" ") %}
        {% if w != "" %}
          {{prefix.id}}{{w.id}}_{{suffix.id}},
        {% end %}
      {% end %}
    )
  end

  ASCII = build_from_file(UInt8, "0x", "u8", "data/ascii")
  LO    = build_from_file(UInt32, "0x", "u32", "data/lo")
  HI    = build_from_file(UInt32, "0x", "u32", "data/hi")
  V     = build_from_file(UInt8, "0x", "u8", "data/v")
  PAGE  = build_from_file(UInt16, "", "u16", "data/page")
end
