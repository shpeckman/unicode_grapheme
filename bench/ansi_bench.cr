# bench/ansi_bench.cr

require "./bench_helper"

module AnsiBench
  extend self

  PLAIN = BenchHelper::ASCII_LINE

  STYLED = ("\e[1m\e[31mThe\e[0m quick \e[32mbrown\e[0m fox " \
            "\e]8;;https://example.com\a\e[4mjumps\e[24m\e]8;;\a " \
            "over the \e[1mlazy\e[0m \e[33mdog\e[39m. ") * 3
end

sink = 0

puts "ansi width"
Benchmark.ips do |bench|
  bench.report("plain  base") { sink &+= UW.width(AnsiBench::PLAIN) }
  bench.report("plain  ansi") { sink &+= UW::ANSI.width(AnsiBench::PLAIN) }
  bench.report("styled base") { sink &+= UW.width(AnsiBench::STYLED) }
  bench.report("styled ansi") { sink &+= UW::ANSI.width(AnsiBench::STYLED) }
end

puts "\nansi each"
Benchmark.ips do |bench|
  bench.report("styled base") { UW.each(AnsiBench::STYLED) { |_, width| sink &+= width } }
  bench.report("styled ansi") { UW::ANSI.each(AnsiBench::STYLED) { |_, width| sink &+= width } }
end

print "\0" if sink == Int32::MIN
