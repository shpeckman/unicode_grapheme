# unicode_grapheme

Unicode text segmentation for Crystal. Splits byte sequences into extended grapheme clusters per [UAX #29](https://www.unicode.org/reports/tr29/) and reports the terminal column width of each cluster.

Built for TUI work: no allocations, no intermediate `String`s, and cluster slices that point directly into the buffer you passed in.

- Conformant against the full official `GraphemeBreakTest.txt` suite (Unicode 17.0.0)
- Handles CRLF, combining marks, Hangul syllables, regional indicator flags, emoji ZWJ sequences, skin-tone modifiers, and Indic conjuncts (GB9c)
- Compile-time property tables, no runtime initialization and no heap allocation
- Zero dependencies

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  unicode_grapheme:
    github: shpeckman/unicode_grapheme
```

Then run `shards install`.

## Usage

```crystal
require "unicode_grapheme"

UW.each("héllo 🇧🇪") do |cluster, width|
  puts "#{String.new(cluster)} (#{width})"
end
```

Three operations, each with a `String` and a `Bytes` overload:

```crystal
UW.each(input) { |cluster : Bytes, width : Int32| }
UW.width(input) : Int32
UW.count(input) : Int32
```

```crystal
UW.count("e\u0301a\u0301")             # => 2
UW.count("\u{1F468}\u200D\u{1F469}")   # => 1

UW.width("hello")                      # => 5
UW.width("\u4E00")                     # => 2
UW.width("e\u0301")                    # => 1
UW.width("\u{1F1FA}\u{1F1F8}")         # => 2
UW.width("\t")                         # => 0
```

### Cluster slices

`each` yields `Bytes` views into the original buffer. Nothing is copied, so a cluster is only valid for as long as the input is. Materialize with `String.new(cluster)` if you need to keep it:

```crystal
clusters = [] of String
UW.each(line) { |cluster, _| clusters << String.new(cluster) }
```

### Streaming

`UW::Stream` is the push-model counterpart for sources that deliver one codepoint at a time, such as a terminal parser. Feed it decoded codepoints; it returns the completed cluster's `{width, byte_length}` when a boundary is crossed, `nil` while the cluster is still open:

```crystal
stream = UW::Stream.new

stream.feed('e')      # => nil
stream.feed('\u0301') # => nil — the combining mark joins the pending cluster
stream.feed('a')      # => {1, 3} — "e\u0301" is complete: 1 column, 3 bytes

stream.finish         # => {1, 1} — flushes the pending "a" at end of input
```

The caller owns the bytes: track the pending cluster yourself and use the returned byte length to delimit completed ones. Call `finish` at end of input and `reset` to drop all pending state. A `finish` is a hard boundary — a cluster flushed there never joins text fed later, even if the batch API would join it.

Input is assumed to be decoded codepoints (or `Char` via the overload). The byte-level invalid-input guarantees of the batch API do not apply here; decode UTF-8 first, substituting U+FFFD as needed.

### Width policy

Width is computed per cluster, not per codepoint, which is why a flag or a family emoji is two columns rather than the sum of its parts.

| Cluster                                            | Columns |
|----------------------------------------------------|---------|
| Control, CR, LF                                    | 0       |
| Contains an East Asian Wide or Fullwidth codepoint | 2       |
| Regional indicator (flag)                          | 2       |
| Extended pictographic followed by U+FE0F           | 2       |
| Everything else                                    | 1       |

Combining marks, joiners and variation selectors add nothing on their own, so a base character with any number of marks attached stays at the width of its base.

### Invalid input

`Bytes` input is not assumed to be well-formed UTF-8. Overlong encodings, surrogates, out-of-range values and truncated sequences are each treated as a single-byte cluster, so iteration always advances and never loops:

```crystal
UW.each(Bytes[0xFF, 0x41]) { |cluster, _| p cluster.to_a }
# => [255]
# => [65]
```

### Version constants

```crystal
UW::VERSION          # shard version, read at compile time
UW::UNICODE_VERSION  # "17.0.0"
```

## Development

```
make spec          # run the spec suite
make bench         # run the benchmarks
make bench-pinned  # run them pinned to a performance core at realtime priority
make gen           # regenerate the property tables
make gen-check     # fail if the committed tables are stale
make clean         # remove caches (tool/.ucd, lib, .shards)
```

The spec suite downloads `GraphemeBreakTest.txt` for the declared `UNICODE_VERSION` and caches it under `spec/fixtures/`.

## Property tables

`src/unicode_grapheme/data/` holds the generated tables: a 128-byte ASCII table, a run-length encoded `lo`/`hi`/`v` range set, and a `page` index that narrows lookups to a short scan. Each entry packs the grapheme break class, Indic conjunct break class, extended pictographic flag and wide flag into one byte. Hangul syllables are computed arithmetically instead of being tabulated.

`tool/gen_tables.py` regenerates all of it from the UCD:

```
python3 tool/gen_tables.py           # write src/unicode_grapheme/data
python3 tool/gen_tables.py --check   # exit 1 if the tables are stale
```

It reads the target version from `UNICODE_VERSION` in `src/unicode_grapheme.cr`, pulls `GraphemeBreakProperty.txt`, `DerivedCoreProperties.txt`, `emoji-data.txt` and `EastAsianWidth.txt`, and caches them gzipped under `tool/.ucd/<version>/`. Python 3 standard library only.

Bumping Unicode versions is a one-line change to `UNICODE_VERSION` followed by `make gen && make spec` — the conformance fixture is fetched for the same version.

## License

MIT. See [LICENSE](LICENSE).
