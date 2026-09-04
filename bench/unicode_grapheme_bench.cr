# bench/unicode_grapheme_bench.cr

require "./bench_helper"

corpus = BenchHelper.corpus
sink   = 0

puts "each"
Benchmark.ips do |bench|
  corpus.each do |name, text|
    bytes = text.to_slice
    bench.report(name) do
      UW.each(bytes) { |_cluster, width| sink &+= width }
    end
  end
end

puts "\nwidth"
Benchmark.ips do |bench|
  corpus.each do |name, text|
    bytes = text.to_slice
    bench.report(name) do
      sink &+= UW.width(bytes)
    end
  end
end

puts "\ncount"
Benchmark.ips do |bench|
  corpus.each do |name, text|
    bytes = text.to_slice
    bench.report(name) do
      sink &+= UW.count(bytes)
    end
  end
end

puts "\nfit"
Benchmark.ips do |bench|
  corpus.each do |name, text|
    bytes = text.to_slice
    bench.report(name) do
      sink &+= UW.fit(bytes, 40)[0]
    end
  end
end

puts "\nskip"
Benchmark.ips do |bench|
  corpus.each do |name, text|
    bytes = text.to_slice
    bench.report(name) do
      sink &+= UW.skip(bytes, 40)[0]
    end
  end
end

print "\0" if sink == Int32::MIN
