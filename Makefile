.PHONY: build install clean uninstall start

SCREENSAVER_NAME = LiveScreensaver.saver
INSTALL_DIR = $(HOME)/Library/Screen\ Savers
BUILD_DIR = build

build:
	rm -rf $(BUILD_DIR)/$(SCREENSAVER_NAME)
	mkdir -p $(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/MacOS
	mkdir -p $(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/Resources
	swiftc -emit-library \
		-o $(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/MacOS/LiveScreensaver \
		-module-name LiveScreensaver \
		-framework ScreenSaver \
		-framework AVFoundation \
		-framework Cocoa \
		-framework Quartz \
		screensaver.swift
	cp Info.plist $(BUILD_DIR)/$(SCREENSAVER_NAME)/Contents/Info.plist

install: build
	cp -r $(BUILD_DIR)/$(SCREENSAVER_NAME) $(INSTALL_DIR)/

clean:
	rm -rf $(BUILD_DIR)

uninstall:
	rm -rf $(INSTALL_DIR)/$(SCREENSAVER_NAME)

start:
	open /System/Library/CoreServices/ScreenSaverEngine.app
