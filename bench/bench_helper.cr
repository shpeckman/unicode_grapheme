# bench/bench_helper.cr

require "benchmark"
require "../src/unicode_grapheme"

module BenchHelper
  extend self

  ASCII_LINE = "The quick brown fox jumps over the lazy dog. " * 4

  CJK_LINE = "\u4E00\u4E8C\u4E09\u56DB\u4E94\u516D\u4E03\u516B\u4E5D\u5341" * 8

  EMOJI_LINE = ("\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}" \
                "\u{1F600}\u{1F1FA}\u{1F1F8}\u2764\uFE0F") * 6

  HANGUL_LINE = "\uAC00\uAC01\uAC04\uAC07\uAC09\uAC0B\uAC1B\uAC1C\uAC24\uAC25" * 8

  MIXED_LINE = "Hello \u4E16\u754C \u{1F44B}\u{1F3FB}, caf\u00E9 \u0915\u094D\u0915 " \
               "\u{1F1EB}\u{1F1F7}\u{1F1E9}\u{1F1EA} test. " * 4

  def corpus : Array({String, String})
    [
      {"ascii",  ASCII_LINE},
      {"cjk",    CJK_LINE},
      {"hangul", HANGUL_LINE},
      {"emoji",  EMOJI_LINE},
      {"mixed",  MIXED_LINE},
    ]
  end
end
