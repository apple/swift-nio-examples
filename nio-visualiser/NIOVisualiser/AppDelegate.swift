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

import Cocoa
import SwiftUI
import Combine
import NIO
import Foundation
import NIOVisualiserLibrary


let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    var window: NSWindow!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")

        let collector = Collector()
        
        window.contentView = NSHostingView(rootView:
            ContentView(handlerInfosState: HandlerInfosState(publisher: collector.$handlerInfos),
                        transmissionState: TransmissionState(publisher: collector.messagePublisher.transmissionHeuristics()))
        )
        
        _ = doIt(group: group, collector: collector)

        //collector.save(handlerInfos: CollectorData.handlerInfos)
        
        window.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

}

