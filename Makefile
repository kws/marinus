.PHONY: build build-macos test test-linux test-macos test-windows test-contracts test-desktop check check-macos clean

PYTHON ?= python3

build: build-macos

build-macos:
	$(MAKE) -C backends/macos build

test: test-linux test-contracts
	@if [ "$$(uname -s)" = Darwin ]; then $(MAKE) test-macos; fi

test-linux:
	MARINUS_LINUX_FIXTURE_DIR="$(CURDIR)/backends/linux/results/fixtures" $(PYTHON) -m unittest discover -s backends/linux -v
	$(PYTHON) scripts/check-contracts.py backends/linux/results/fixtures

test-macos:
	MARINUS_FIXTURE_DIR="$(CURDIR)/backends/macos/results/fixtures" $(MAKE) -C backends/macos test
	$(PYTHON) scripts/check-contracts.py backends/macos/results/fixtures

test-windows:
	dotnet run --project backends/windows/tests/Marinus.Windows.Tests -c Release -- --emit-fixtures backends/windows/results/fixtures
	$(PYTHON) scripts/check-contracts.py backends/windows/results/fixtures

test-contracts:
	$(PYTHON) scripts/check-contracts.py

test-desktop:
	cd desktop && npm test && npm run build
	cd desktop && cargo test --locked --manifest-path src-tauri/Cargo.toml

check: test-linux test-contracts
	@if [ "$$(uname -s)" = Darwin ]; then $(MAKE) check-macos; fi

check-macos:
	MARINUS_FIXTURE_DIR="$(CURDIR)/backends/macos/results/fixtures" $(MAKE) -C backends/macos check
	$(PYTHON) scripts/check-contracts.py backends/macos/results/fixtures

clean:
	$(MAKE) -C backends/macos clean
