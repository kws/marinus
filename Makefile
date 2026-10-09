.PHONY: build build-macos test test-linux test-macos test-windows test-contracts check check-macos clean

PYTHON ?= python3

build: build-macos

build-macos:
	$(MAKE) -C backends/macos build

test: test-linux test-contracts
	@if [ "$$(uname -s)" = Darwin ]; then $(MAKE) test-macos; fi

test-linux:
	$(PYTHON) -m unittest discover -s backends/linux -v

test-macos:
	$(MAKE) -C backends/macos test

test-windows:
	dotnet run --project backends/windows/tests/Marinus.Windows.Tests -c Release -- --emit-fixtures backends/windows/results/fixtures
	$(PYTHON) scripts/check-contracts.py backends/windows/results/fixtures

test-contracts:
	$(PYTHON) scripts/check-contracts.py

check: test-linux test-contracts
	@if [ "$$(uname -s)" = Darwin ]; then $(MAKE) check-macos; fi

check-macos:
	$(MAKE) -C backends/macos check

clean:
	$(MAKE) -C backends/macos clean
