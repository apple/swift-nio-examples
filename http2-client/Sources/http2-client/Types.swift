//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOHTTP1

struct HostAndPort: Equatable, Hashable {
    var host: String
    var port: Int
}

public struct HTTPRequest {
    class _Storage {
        var method: HTTPMethod
        var target: String
        var version: HTTPVersion
        var headers: [(String, String)]
        var body: [UInt8]?
        var trailers: [(String, String)]?

        init(method: HTTPMethod = .GET,
             target: String,
             version: HTTPVersion,
             headers: [(String, String)],
             body: [UInt8]?,
             trailers: [(String, String)]?) {
            self.method = method
            self.target = target
            self.version = version
            self.headers = headers
            self.body = body
            self.trailers = trailers
        }

    }

    private var _storage: _Storage

    public init(method: HTTPMethod = .GET,
                target: String,
                version: HTTPVersion = HTTPVersion(major: 1, minor: 1),
                headers: [(String, String)],
                body: [UInt8]?,
                trailers: [(String, String)]?) {
        self._storage = _Storage(method: method,
                                 target: target,
                                 version: version,
                                 headers: headers,
                                 body: body,
                                 trailers: trailers)
    }
}

extension HTTPRequest._Storage {
    func copy() -> HTTPRequest._Storage {
        return HTTPRequest._Storage(method: self.method,
                                            target: self.target,
                                            version: self.version,
                                            headers: self.headers,
                                            body: self.body,
                                            trailers: self.trailers)
    }
}

extension HTTPRequest {
    public var method: HTTPMethod {
        get {
            return self._storage.method
        }
        set {
            if !isKnownUniquelyReferenced(&self._storage) {
                self._storage = self._storage.copy()
            }
            self._storage.method = newValue
        }
    }

    public var target: String {
        get {
            return self._storage.target
        }
        set {
            if !isKnownUniquelyReferenced(&self._storage) {
                self._storage = self._storage.copy()
            }
            self._storage.target = newValue
        }
    }

    public var version: HTTPVersion {
        get {
            return self._storage.version
        }
        set {
            if !isKnownUniquelyReferenced(&self._storage) {
                self._storage = self._storage.copy()
            }
            self._storage.version = newValue
        }
    }

    public var headers: [(String, String)] {
        get {
            return self._storage.headers
        }
        set {
            if !isKnownUniquelyReferenced(&self._storage) {
                self._storage = self._storage.copy()
            }
            self._storage.headers = newValue
        }
    }

    public var body: [UInt8]? {
        get {
            return self._storage.body
        }
        set {
            if !isKnownUniquelyReferenced(&self._storage) {
                self._storage = self._storage.copy()
            }
            self._storage.body = newValue
        }
    }

    public var trailers: [(String, String)]? {
        get {
            return self._storage.trailers
        }
        set {
            if !isKnownUniquelyReferenced(&self._storage) {
                self._storage = self._storage.copy()
            }
            self._storage.trailers = newValue
        }
    }
}
