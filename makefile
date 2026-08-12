# Makefile
SHELL := bash

CRYSTAL = crystal
PYTHON  = python3
SPEC    = --error-trace
BENCH   = --release
TC      = \\e[4;33m

BENCHES = $(wildcard bench/*_bench.cr)
GEN     = tool/gen_tables.py
CACHES  = tool/.ucd lib .shards

banner = @echo -e "\\n$(TC)== $(1) ==\\e[0m\\n"

define run_spec
	$(call banner,SPEC SUITE)
	@$(CRYSTAL) spec $(SPEC)
endef

define run_bench
	$(call banner,BENCH SUITE)
	@for ex in $(BENCHES); do \
		$(CRYSTAL) run $(BENCH) "$$ex"; \
		echo; \
	done
endef

define run_bench_pinned
	$(call banner,BENCH SUITE (PINNED))
	@cpu=$$(tr ',' '\n' < /sys/devices/cpu_core/cpus 2>/dev/null | tail -n1 | cut -d- -f2); \
	if [[ -n $$cpu ]]; then \
		class="performance core"; \
	else \
		cpu=$$(( $$(nproc) - 1 )); \
		class="last core, no hybrid topology reported"; \
	fi; \
	if chrt -f 99 taskset -c "$$cpu" true 2>/dev/null; then \
		pin="chrt -f 99 taskset -c $$cpu"; \
		echo "pinned: cpu $$cpu ($$class), realtime priority"; \
	elif taskset -c "$$cpu" true 2>/dev/null; then \
		pin="taskset -c $$cpu"; \
		echo "pinned: cpu $$cpu ($$class), normal priority"; \
	else \
		pin=""; \
		echo "note: pinning unavailable, running unpinned"; \
	fi; \
	for ex in $(BENCHES); do \
		$$pin $(CRYSTAL) run $(BENCH) "$$ex"; \
		echo; \
	done
endef

define run_gen
	$(call banner,TABLE GEN)
	@$(PYTHON) $(GEN)
endef

define run_gen_check
	$(call banner,TABLE CHECK)
	@$(PYTHON) $(GEN) --check
endef

define run_clean
	$(call banner,CLEAN)
	@for path in $(CACHES); do \
		if [[ -e $$path ]]; then \
			rm -rf "$$path"; \
			echo "removed $$path"; \
		fi; \
	done
endef

.PHONY: all test spec bench bench-pinned gen gen-check clean

all: test

test:
	$(run_spec)
	$(run_bench)

spec:
	$(run_spec)

bench:
	$(run_bench)

bench-pinned:
	$(run_bench_pinned)

gen:
	$(run_gen)

gen-check:
	$(run_gen_check)

clean:
	$(run_clean)