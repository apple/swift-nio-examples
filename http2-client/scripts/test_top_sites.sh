#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the SwiftNIO open source project
##
## Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
## Licensed under Apache License v2.0
##
## See LICENSE.txt for license information
## See CONTRIBUTORS.txt for the list of SwiftNIO project authors
##
## SPDX-License-Identifier: Apache-2.0
##
##===----------------------------------------------------------------------===##

set -eu

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$here/.."

tmp=$(mktemp -d /tmp/.test_top_sites_XXXXXX)
nio_errors=0

echo -n 'compiling...'
swift run http2-client https://google.com > "$tmp/compiling" 2>&1 || { cat "$tmp/compiling"; exit 1; }
echo OK

while read site; do
    url="https://$site"
    is_http2=true
    echo "testing $url"
    if curl --connect-timeout 10 --http2-prior-knowledge -Iv "$url" > "$tmp/curl" 2>&1; then
        if grep -q HTTP/1 "$tmp/curl"; then
            echo -n 'curl HTTP/1.x only'
            is_http2=false
        else
            echo -n 'curl HTTP/2 ok    '
        fi
    else
        is_http2=false
        echo -n 'curl failed       '
    fi

    if swift run http2-client "$url" > "$tmp/nio"; then
        echo '; NIO ok'
    else
        if grep -q serverDoesNotSpeakHTTP2 "$tmp/nio"; then
            if $is_http2; then
                nio_errors=$(( nio_errors + 1 ))
                echo '; NIO WRONGLY detected no HTTP/2'
            else
                echo '; NIO correctly detected no HTTP/2'
            fi
        else
            nio_errors=$(( nio_errors + 1 ))
            echo '; NIO DID NOT DETECT MISSING HTTP/2'
            echo "--- NIO DEBUG INFO: BEGIN ---"
            cat "$tmp/nio"
            echo "--- NIO DEBUG INFO: END ---"
        fi
    fi
done < <(curl -qs https://moz.com/top-500/download?table=top500Domains | sed 1d | head -n 100 | cut -d, -f2 | tr -d '"' | \
    grep -v -e ^qq.com -e ^go.com -e ^who.int)
rm -rf "$tmp"
exit "$nio_errors"
