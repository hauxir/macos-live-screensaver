#!/bin/bash

set -e

rm -rf build/LiveScreensaver.saver

mkdir -p build/LiveScreensaver.saver/Contents/MacOS
mkdir -p build/LiveScreensaver.saver/Contents/Resources

swiftc -emit-library \
  -o build/LiveScreensaver.saver/Contents/MacOS/LiveScreensaver \
  -module-name LiveScreensaver \
  -framework ScreenSaver \
  -framework AVFoundation \
  -framework Cocoa \
  screensaver.swift

cp Info.plist build/LiveScreensaver.saver/Contents/Info.plist
