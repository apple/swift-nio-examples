#!/bin/bash

set -eu
set -x

export COCOAPODS_DISABLE_STATS=true
pod install
xcodebuild -workspace NIOSMTP.xcworkspace -scheme NIOSMTP -arch x86_64 -sdk iphonesimulator
