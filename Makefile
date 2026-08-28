.PHONY: build install clean uninstall start verify test lint format notarize assess

SCREENSAVER_NAME = LiveScreensaver.saver
INSTALL_DIR = $(HOME)/Library/Screen\ Savers
BUILD_DIR = build

# Marketing version, e.g. 1.2.0. Release CI passes the git tag with its
# leading "v" stripped; a local build gets 0.0.0 so it is obviously not a
# release.
VERSION ?= 0.0.0
# Monotonic build number. Release CI passes the run number.
BUILD_NUMBER ?= 0

# Architectures to build and merge into the shipped binary. Without an explicit
# -target, swiftc emits a single slice for whatever the build machine happens to
# be -- which on CI means Apple Silicon only, silently excluding every Intel Mac.
ARCHS ?= arm64 x86_64
# Minimum macOS. Must stay in step with LSMinimumSystemVersion in Info.plist.
# Without this the deployment target is whatever SDK the build machine has, so a
# runner image upgrade would raise the minimum OS without anyone noticing.
MACOS_MIN ?= 13.0

# Code signing identity. The default "-" is an ad-hoc signature, which is fine
# for a local build but is rejected by Gatekeeper on any machine that did not
# build it. Release CI overrides this with a Developer ID Application identity.
SIGN_IDENTITY ?= -

SWIFT_FLAGS = -emit-library -module-name LiveScreensaver \
	-framework ScreenSaver -framework AVFoundation \
	-framework Cocoa -framework Quartz
# The .saver is built as a single module from both directories: the pure logic
# that SwiftPM also builds and tests on its own, plus the AppKit layer that can
# only run inside a screensaver host.
CORE_SOURCES = $(wildcard Sources/LiveScreensaverCore/*.swift)
APP_SOURCES = $(wildcard Screensaver/*.swift)
SOURCES = $(CORE_SOURCES) $(APP_SOURCES)

build:
	rm -rf $(BUILD_DIR)/$(SCREENSAVER_NAME) $(BUILD_DIR)/slices
	mkdir -p $(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/MacOS
	mkdir -p $(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/Resources
	mkdir -p $(BUILD_DIR)/slices
	@set -e; for arch in $(ARCHS); do \
		echo "Compiling $$arch slice (macOS $(MACOS_MIN) minimum)"; \
		swiftc $(SWIFT_FLAGS) \
			-target $$arch-apple-macos$(MACOS_MIN) \
			-o $(BUILD_DIR)/slices/LiveScreensaver-$$arch \
			$(SOURCES); \
	done
	lipo -create -output \
		$(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/MacOS/LiveScreensaver \
		$(foreach arch,$(ARCHS),$(BUILD_DIR)/slices/LiveScreensaver-$(arch))
	rm -rf $(BUILD_DIR)/slices
	cp Info.plist $(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/Info.plist
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" \
		$(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/Info.plist
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" \
		$(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/Info.plist
	qlmanage -t -s 267 -o $(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/Resources/ thumbnail.svg
	mv $(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/Resources/thumbnail.svg.png $(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/Resources/thumbnail.png
	@set -e; \
	if [ "$(SIGN_IDENTITY)" = "-" ]; then \
		echo "Ad-hoc signing (local build; will not pass Gatekeeper elsewhere)"; \
		codesign --force --sign - $(BUILD_DIR)/$(SCREENSAVER_NAME); \
	else \
		echo "Signing with: $(SIGN_IDENTITY)"; \
		codesign --force --options runtime --timestamp \
			--sign "$(SIGN_IDENTITY)" $(BUILD_DIR)/$(SCREENSAVER_NAME); \
	fi

install: build
	cp -r $(BUILD_DIR)/$(SCREENSAVER_NAME) $(INSTALL_DIR)/

# Assert the built bundle actually contains everything a .saver needs, so a
# silently-broken build fails here rather than on a user's machine.
verify:
	@set -e; \
	bundle="$(BUILD_DIR)/$(SCREENSAVER_NAME)"; \
	for f in "Contents/MacOS/LiveScreensaver" "Contents/Info.plist" "Contents/Resources/thumbnail.png"; do \
		test -f "$$bundle/$$f" || { echo "missing: $$f"; exit 1; }; \
	done; \
	plutil -lint "$$bundle/Contents/Info.plist"; \
	test "$$(plutil -extract NSPrincipalClass raw "$$bundle/Contents/Info.plist")" = "LiveScreensaverView" \
		|| { echo "NSPrincipalClass is not LiveScreensaverView"; exit 1; }; \
	test "$$(plutil -extract CFBundleShortVersionString raw "$$bundle/Contents/Info.plist")" = "$(VERSION)" \
		|| { echo "version was not stamped into Info.plist"; exit 1; }; \
	test "$$(plutil -extract LSMinimumSystemVersion raw "$$bundle/Contents/Info.plist")" = "$(MACOS_MIN)" \
		|| { echo "LSMinimumSystemVersion does not match MACOS_MIN ($(MACOS_MIN))"; exit 1; }; \
	for arch in $(ARCHS); do \
		lipo -archs "$$bundle/Contents/MacOS/LiveScreensaver" | grep -qw "$$arch" \
			|| { echo "missing architecture: $$arch"; exit 1; }; \
	done; \
	echo "Architectures: $$(lipo -archs "$$bundle/Contents/MacOS/LiveScreensaver")"; \
	codesign --verify --verbose "$$bundle"; \
	echo "Bundle verified"

# Submit the built bundle to Apple's notary service and staple the ticket, so
# the screensaver opens without a Gatekeeper warning on a machine that has never
# seen it. Requires an App Store Connect API key; see README.
notarize:
	@set -e; \
	test -n "$$ASC_KEY_PATH" || { echo "ASC_KEY_PATH is not set"; exit 1; }; \
	test -n "$$ASC_KEY_ID" || { echo "ASC_KEY_ID is not set"; exit 1; }; \
	test -n "$$ASC_ISSUER_ID" || { echo "ASC_ISSUER_ID is not set"; exit 1; }; \
	echo "Submitting for notarisation (this can take a few minutes)"; \
	ditto -c -k --keepParent \
		$(BUILD_DIR)/$(SCREENSAVER_NAME) $(BUILD_DIR)/notarize.zip; \
	xcrun notarytool submit $(BUILD_DIR)/notarize.zip \
		--key "$$ASC_KEY_PATH" \
		--key-id "$$ASC_KEY_ID" \
		--issuer "$$ASC_ISSUER_ID" \
		--wait; \
	rm -f $(BUILD_DIR)/notarize.zip; \
	xcrun stapler staple $(BUILD_DIR)/$(SCREENSAVER_NAME); \
	xcrun stapler validate $(BUILD_DIR)/$(SCREENSAVER_NAME); \
	echo "Notarised and stapled"

# What Gatekeeper will decide on a user's machine. Only meaningful after a
# Developer ID signature and notarisation; an ad-hoc build is expected to fail.
assess:
	spctl -a -vvv -t install $(BUILD_DIR)/$(SCREENSAVER_NAME)

test:
	swift test

lint:
	swift-format lint --strict --recursive .

format:
	swift-format format --in-place --recursive .

clean:
	rm -rf $(BUILD_DIR) .build

uninstall:
	rm -rf $(INSTALL_DIR)/$(SCREENSAVER_NAME)

start:
	open /System/Library/CoreServices/ScreenSaverEngine.app
