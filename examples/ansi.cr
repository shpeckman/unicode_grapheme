# examples/ansi.cr

# Measuring, iterating and clipping text that carries ANSI escape
# sequences, using the UW::ANSI operations.
#
#   crystal run examples/ansi.cr

require "../src/unicode_grapheme"

LINE = "\e[1m\e[31merror:\e[0m \e[4mdisk full\e[0m " \
       "(\e]8;;https://example.com/logs\alogs\e]8;;\a) \u{1F6A8}"

# Escape sequences are zero-width clusters of their own, so styled text
# measures by the cells it will occupy on the terminal.

puts LINE
puts "bytes:         #{LINE.bytesize}"
puts "naive width:   #{UW.width(LINE)} (escape bytes counted as text)"
puts "visible width: #{UW::ANSI.width(LINE)}"
puts "clusters:      #{UW::ANSI.count(LINE)} (escapes count as clusters)"
puts

# Iterating: every cluster is yielded with its column width, escape
# sequences included.

puts "clusters of \"\\e[31mred\\e[0m\":"
UW::ANSI.each("\e[31mred\e[0m") do |cluster, width|
  text  = String.new(cluster)
  label = text.starts_with?('\e') ? text.inspect : text
  puts "  #{label} width #{width}"
end
puts

# fit clips to a column budget without splitting a cluster or an escape
# sequence. The cut may land before the reset, so guard the terminal.

budget = 20
fit_bytes, fit_width = UW::ANSI.fit(LINE, budget)
puts "fit #{budget}: |#{LINE.byte_slice(0, fit_bytes)}\e[0m#{" " * (budget - fit_width)}|"
puts

# skip is the dual: it consumes whole columns from the front. Escape
# sequences before the cut point are dropped with the prefix, so skip is
# best used at a style boundary.

skip_bytes, skipped_width = UW::ANSI.skip(LINE, 7)
puts "skip 7: #{LINE.byte_slice(skip_bytes)}\e[0m (skipped #{skipped_width} columns)"
