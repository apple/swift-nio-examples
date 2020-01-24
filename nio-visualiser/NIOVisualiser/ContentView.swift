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

import SwiftUI
import NIOVisualiserLibrary


struct ContentView : View {
    @ObservedObject var handlerInfosState: HandlerInfosState
    @ObservedObject var transmissionState: TransmissionState
    
    var body: some View {
            ChannelPipelineView(handlerInfosState: self.handlerInfosState,
                                transmissionState: self.transmissionState)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if DEBUG
struct ContentView_Previews : PreviewProvider {
    static var previews: some View {
        let collector = Collector()
        return ContentView(handlerInfosState: HandlerInfosState(publisher: collector.$handlerInfos),
                           transmissionState: TransmissionState(publisher: collector.messagePublisher.transmissionHeuristics())
        )
    }
}
#endif
