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

import NIOVisualiserLibrary

import SwiftUI

private extension ChannelHandlerPort {
    var color: Color {
        switch self {
        case .in:
            return Color.green
        case .out:
            return Color.green.opacity(0.2)
        }
    }
}

struct ChannelHandlerSimplePortView : View {
    var flash: Bool
    
    var text: String = ""

    var port: ChannelHandlerPort?
    
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .circular)
            .frame(width: 400, height: 300, alignment: .center)
            .foregroundColor(flash ? self.port!.color : Color.gray)
    }
}

#if DEBUG
struct ChannelHandlerSimplePortView_Previews : PreviewProvider {
    static var previews: some View {
        Group {
            List {
                ChannelHandlerSimplePortView(flash: true, port: .in)
                ChannelHandlerSimplePortView(flash: true, port: .out)
                ChannelHandlerSimplePortView(flash: false, port: .in)
            }.environment(\.colorScheme, .light)
            List {
                ChannelHandlerSimplePortView(flash: true, port: .in)
                ChannelHandlerSimplePortView(flash: true, port: .out)
                ChannelHandlerSimplePortView(flash: false, port: .in)
            }.environment(\.colorScheme, .dark)
        }
    }
}
#endif
