#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftNIO open source project
##
## Copyright (c) 2025 Apple Inc. and the SwiftNIO project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftNIO project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -uo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

default_package_directories="TLSify UniversalBootstrapDemo backpressure-file-io-channel http-responsiveness-server connect-proxy http2-client http2-server json-rpc nio-launchd"
default_project_directories="NIOSMTP"

# --
strict_concurrency="${STRICT_CONCURRENCY:-""}"
xcode_build_enabled="${XCODE_BUILD_ENABLED:-""}"

package_directories="${SWIFT_PACKAGE_DIRECTORIES:-$default_package_directories}"
project_directories="${XCODE_PROJECT_DIRECTORIES:-$default_project_directories}"

# --

if [ -n "$strict_concurrency" ]; then
  swift_build_command="swift build -Xswiftc -warnings-as-errors --explicit-target-dependency-import-check error -Xswiftc -require-explicit-sendable"
else
  swift_build_command="swift build"
fi

xcode_build_command="xcodebuild -project NIOSMTP.xcodeproj -scheme NIOSMTP -arch x86_64 -sdk iphonesimulator"

for directory in $package_directories; do
  log "Building: $directory"
  $swift_build_command --package-path "$directory"
done

if [ -n "$xcode_build_enabled" ]; then
for directory in $project_directories; do
    log "Building: $directory"
    cd "$directory" || fatal "Could not cd to ${directory}."
    $xcode_build_command
    cd .. || fatal "Could not cd to parent."
  done
fi