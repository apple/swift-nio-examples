#!/bin/bash

set -eu
set -x

xcodebuild -project NIOSMTP.xcodeproj -scheme NIOSMTP -arch x86_64 -sdk iphonesimulator
