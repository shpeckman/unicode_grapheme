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
    ("lo", 8, "{:05X}"),
    ("hi", 8, "{:05X}"),
    ("v", 16, "{:02X}"),
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


def build_ranges(values):
    ranges = []
    start = 0

    while start <= MAXIMUM:
        value = values[start]
        end = start
        while end < MAXIMUM and values[end + 1] == value:
            end += 1

        if value != 0 and end >= ASCII_LIMIT and not (
            start >= HANGUL_FIRST and end <= HANGUL_LAST
        ):
            ranges.append((start, end, value))

        start = end + 1

    return ranges


def build_page(ranges):
    page = []
    index = 0

    for start in range(0, MAXIMUM + PAGE_SIZE + 1, PAGE_SIZE):
        while index < len(ranges) and ranges[index][1] < start:
            index += 1
        page.append(index)

    return page


def build_tables(values):
    ranges = build_ranges(values)
    if len(ranges) > 0xFFFF:
        raise SystemExit(f"{len(ranges)} ranges exceed the UInt16 page index")

    return {
        "ascii": list(values[:ASCII_LIMIT]),
        "lo": [low for low, _, _ in ranges],
        "hi": [high for _, high, _ in ranges],
        "v": [value for _, _, value in ranges],
        "page": build_page(ranges),
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

    print(f"unicode {version}: {len(tables['lo'])} ranges, {len(tables['page'])} pages")
    return 0


if __name__ == "__main__":
    sys.exit(main())