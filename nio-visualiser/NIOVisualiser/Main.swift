//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation
import NIO
import NIOVisualiserLibrary

func doIt(group: EventLoopGroup, collector: Collector) -> EventLoopFuture<Void> {
    let eventLoop = group.next()
    let allDonePromise = eventLoop.makePromise(of: Void.self)
    
    let email = Email(senderName: "Sender",
                      senderEmail: "sender@abc.com",
                      recipientName: "Receiver",
                      recipientEmail: "receiver@abc.com",
                      subject: "Subject",
                      body: "SwiftNIO Visualiser is cool !")
    let commHandler: (String) -> Void = { str in
        DispatchQueue.main.async {
            print(str)
        }
    }
        
    sendEmail(email, group: group, collector: collector, communicationHandler: commHandler) { maybeError in
        DispatchQueue.global().async {
            if let error = maybeError {
                print("ERROR: \(error)\n")
                allDonePromise.fail(error)
            } else {
                print("✅")
                allDonePromise.succeed(())
            }
            
        }
    }
    
    return allDonePromise.futureResult
}
