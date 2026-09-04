# tool/gen_tables.py

import argparse
import gzip
import re
import sys
import urllib.request
from pathlib import Path

UCD_URL = "https://www.unicode.org/Public/{version}/ucd/{path}"

VERSION_PATTERN = re.compile(r'UNICODE_VERSION\s*=\s*"([^"]+)"')
ENTRY_PATTERN = re.compile(
    r"^\s*([0-9A-Fa-f]{4,6})(?:\.\.([0-9A-Fa-f]{4,6}))?\s*;\s*([^#]*)"
)

MAXIMUM = 0x10FFFF
PAGE_SIZE = 0x100
ASCII_LIMIT = 0x80
HANGUL_FIRST = 0xAC00
HANGUL_LAST = 0xD7A3
HANGUL_CYCLE = 28

# Runtime layout constants, mirrored in src/unicode_grapheme/props.cr and
# src/unicode_grapheme/segmenter.cr.
UNIFORM_BIT = 0x8000
HANGUL_LV = 0x2C
HANGUL_LVT = 0x2D

# Blocks the runtime fast paths treat as uniformly wide and
# break-isolated; check_fast_blocks fails the build if a Unicode update
# ever changes them.
FAST_WIDE_BLOCKS = (
    (0x3400, 0x4DBF),
    (0x4E00, 0x9FFF),
    (0xF900, 0xFAFF),
)

GCB_MASK = 0x0F
PICTOGRAPHIC_MASK = 0x10
WIDE_MASK = 0x20
INCB_SHIFT = 6

GCB_VALUES = {
    "Other": 0,
    "CR": 1,
    "LF": 2,
    "Control": 3,
    "Extend": 4,
    "ZWJ": 5,
    "Regional_Indicator": 6,
    "Prepend": 7,
    "SpacingMark": 8,
    "L": 9,
    "V": 10,
    "T": 11,
    "LV": 12,
    "LVT": 13,
}

INCB_VALUES = {
    "None": 0,
    "Consonant": 1,
    "Linker": 2,
    "Extend": 3,
}

WIDE_VALUES = ("W", "F")

WIDE_DEFAULTS = (
    (0x3400, 0x4DBF),
    (0x4E00, 0x9FFF),
    (0xF900, 0xFAFF),
    (0x20000, 0x2FFFD),
    (0x30000, 0x3FFFD),
)

SOURCES = (
    ("gcb", "auxiliary/GraphemeBreakProperty.txt"),
    ("incb", "DerivedCoreProperties.txt"),
    ("pictographic", "emoji/emoji-data.txt"),
    ("wide", "EastAsianWidth.txt"),
)

LAYOUT = (
    ("ascii", 16, "{:02X}"),
    ("block", 16, "{:02X}"),
    ("page", 12, "{:d}"),
)


def unicode_version(source):
    match = VERSION_PATTERN.search(source.read_text())
    if match is None:
        raise SystemExit(f"no UNICODE_VERSION in {source}")
    return match.group(1)


def fetch(version, path, cache_dir):
    cached = cache_dir / version / (Path(path).name + ".gz")
    if cached.exists():
        return gzip.decompress(cached.read_bytes()).decode("utf-8")

    url = UCD_URL.format(version=version, path=path)
    with urllib.request.urlopen(url) as response:
        body = response.read()

    cached.parent.mkdir(parents=True, exist_ok=True)
    cached.write_bytes(gzip.compress(body, 9))
    return body.decode("utf-8")


def entries(text):
    for line in text.splitlines():
        match = ENTRY_PATTERN.match(line)
        if match is None:
            continue
        low = int(match.group(1), 16)
        high = int(match.group(2), 16) if match.group(2) else low
        fields = [field.strip() for field in match.group(3).split(";")]
        yield low, high, fields


def assign(values, low, high, mask, bits):
    for codepoint in range(low, high + 1):
        values[codepoint] = (values[codepoint] & ~mask) | bits


def apply_gcb(values, text):
    for low, high, fields in entries(text):
        gcb = GCB_VALUES.get(fields[0])
        if gcb is not None:
            assign(values, low, high, GCB_MASK, gcb)


def apply_incb(values, text):
    for low, high, fields in entries(text):
        if len(fields) < 2 or fields[0] != "InCB":
            continue
        incb = INCB_VALUES.get(fields[1])
        if incb:
            assign(values, low, high, 0xFF << INCB_SHIFT, incb << INCB_SHIFT)


def apply_pictographic(values, text):
    for low, high, fields in entries(text):
        if fields[0] == "Extended_Pictographic":
            assign(values, low, high, PICTOGRAPHIC_MASK, PICTOGRAPHIC_MASK)


def apply_wide(values, text):
    for low, high in WIDE_DEFAULTS:
        assign(values, low, high, WIDE_MASK, WIDE_MASK)

    for low, high, fields in entries(text):
        wide = WIDE_MASK if fields[0] in WIDE_VALUES else 0
        assign(values, low, high, WIDE_MASK, wide)


APPLIERS = {
    "gcb": apply_gcb,
    "incb": apply_incb,
    "pictographic": apply_pictographic,
    "wide": apply_wide,
}


def build_values(version, cache_dir):
    values = bytearray(MAXIMUM + 1)
    for name, path in SOURCES:
        APPLIERS[name](values, fetch(version, path, cache_dir))
    return values


def check_fast_blocks(values):
    """Guard the invariants the runtime fast paths rely on.

    The segmenter consumes whole runs of the CJK ideograph and Hangul
    syllable blocks without touching the break-state machine, assuming
    every such codepoint is wide and break-isolated (and that Hangul
    syllables alternate LV/LVT with a period of 28). If a Unicode update
    ever breaks those assumptions, table generation fails here instead
    of shipping a silently wrong segmenter.
    """
    for first, last in FAST_WIDE_BLOCKS:
        for codepoint in range(first, last + 1):
            if values[codepoint] != WIDE_MASK:
                raise SystemExit(
                    f"U+{codepoint:04X}: fast wide block not uniformly "
                    f"wide/other ({values[codepoint]:#04x})"
                )

    for codepoint in range(HANGUL_FIRST, HANGUL_LAST + 1):
        if (codepoint - HANGUL_FIRST) % HANGUL_CYCLE == 0:
            expect = HANGUL_LV
        else:
            expect = HANGUL_LVT
        if values[codepoint] != expect:
            raise SystemExit(
                f"U+{codepoint:04X}: hangul pattern changed "
                f"({values[codepoint]:#04x})"
            )


def build_flat(values):
    """Two-level flat lookup with one entry per 256-codepoint page.

    A page whose codepoints all share one value stores it inline as
    UNIFORM_BIT | value. Any other page stores the index of a dense
    256-entry block, deduplicated, appended to the block table.
    """
    # Hangul is computed arithmetically at runtime; keep it out of the
    # tables so those pages stay uniform.
    values = bytearray(values)
    for codepoint in range(HANGUL_FIRST, HANGUL_LAST + 1):
        values[codepoint] = 0

    page = []
    blocks = []
    seen = {}

    for start in range(0, MAXIMUM + 1, PAGE_SIZE):
        chunk = bytes(values[start:start + PAGE_SIZE])
        if chunk == chunk[:1] * PAGE_SIZE:
            page.append(UNIFORM_BIT | chunk[0])
            continue

        index = seen.get(chunk)
        if index is None:
            index = len(blocks)
            blocks.append(chunk)
            seen[chunk] = index
        page.append(index)

    if len(blocks) >= UNIFORM_BIT:
        raise SystemExit(f"{len(blocks)} blocks exceed the page index")

    return page, blocks


def build_tables(values):
    check_fast_blocks(values)
    page, blocks = build_flat(values)

    return {
        "ascii": list(values[:ASCII_LIMIT]),
        "page": page,
        "block": [byte for block in blocks for byte in block],
    }


def render(items, per_line, form):
    lines = [
        " ".join(form.format(item) for item in items[start:start + per_line])
        for start in range(0, len(items), per_line)
    ]
    return "\n".join(lines) + "\n"


def main():
    root = Path(__file__).resolve().parent.parent

    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source", type=Path, default=root / "src/unicode_grapheme.cr"
    )
    parser.add_argument(
        "--output", type=Path, default=root / "src/unicode_grapheme/data"
    )
    parser.add_argument("--cache", type=Path, default=root / "tool/.ucd")
    parser.add_argument("--version")
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()

    version = arguments.version or unicode_version(arguments.source)
    tables = build_tables(build_values(version, arguments.cache))

    arguments.output.mkdir(parents=True, exist_ok=True)
    stale = False

    for name, per_line, form in LAYOUT:
        text = render(tables[name], per_line, form)
        path = arguments.output / name

        if arguments.check:
            current = path.read_text() if path.exists() else ""
            if current != text:
                stale = True
                print(f"{path}: stale", file=sys.stderr)
        else:
            path.write_text(text)

    if arguments.check and stale:
        return 1

    print(
        f"unicode {version}: {len(tables['block']) // PAGE_SIZE} blocks, "
        f"{len(tables['page'])} pages"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())