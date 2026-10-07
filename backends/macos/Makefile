.PHONY: build test check ci clean

SWIFT ?= swift
SIGN_IDENTITY ?= -
SWIFTC ?= swiftc

build:
	SWIFT="$(SWIFT)" SIGN_IDENTITY="$(SIGN_IDENTITY)" ./scripts/build-app.sh

test:
	SWIFTC="$(SWIFTC)" ./scripts/test.sh

# Includes an app round trip without requesting Location Services or Keychain access.
check: build
	MARINUS_TEST_APP="$(CURDIR)/dist/Marinus.app" SWIFTC="$(SWIFTC)" ./scripts/test.sh
	plutil -lint packaging/Info.plist packaging/entitlements.plist
	codesign --verify --deep --strict dist/Marinus.app
	./dist/marinus version
	./dist/marinus help >/dev/null

ci: check

clean:
	rm -rf .build dist
