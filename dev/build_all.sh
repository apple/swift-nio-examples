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

set -euo pipefail

log() { printf -- "** %s\n" "$*" >&2; }
error() { printf -- "** ERROR: %s\n" "$*" >&2; }
fatal() { error "$@"; exit 1; }

default_package_directories="$(while read -r manifest; do dirname "$manifest"; done < <(ls -1 ./*/Package.swift))"
default_project_directories="$(while read -r manifest; do dirname "$manifest"; done < <(ls -1 ./*/*.xcodeproj))"

# --
strict_concurrency="${STRICT_CONCURRENCY:-""}"
xcode_build_enabled="${XCODE_BUILD_ENABLED:-""}"
extra_build_flags="${EXTRA_BUILD_FLAGS:-""}"

package_directories="${SWIFT_PACKAGE_DIRECTORIES:-$default_package_directories}"
project_directories="${XCODE_PROJECT_DIRECTORIES:-$default_project_directories}"

# --

if [ -n "$strict_concurrency" ]; then
  swift_build_command="swift build $extra_build_flags -Xswiftc -warnings-as-errors --explicit-target-dependency-import-check error -Xswiftc -require-explicit-sendable"
else
  swift_build_command="swift build $extra_build_flags"
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