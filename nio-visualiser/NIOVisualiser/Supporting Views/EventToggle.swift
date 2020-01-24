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

struct EventToggle: View {
    var bool: Binding<Bool>
    var text: String
    
    var body: some View {
        Toggle(isOn: self.bool) {
            Text(self.text)
        }.frame(width: 200)
    }
}

struct EventToggle_Previews: PreviewProvider {
    
    static let binding: Binding<Bool> = .init(get: { () -> Bool in
        return true
    }) { (value) in
        print(value)
    }
    
    static var previews: some View {
        EventToggle(bool: binding, text: "Binding")
    }
}
