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

import NIO

final class SendEmailHandler: ChannelInboundHandler {
    typealias InboundIn = SMTPResponse
    typealias OutboundIn = Email
    typealias OutboundOut = SMTPRequest
    
    enum Expect {
        case initialMessageFromServer
        case okForOurHello
        case okForOurAuthBegin
        case okAfterUsername
        case okAfterPassword
        case okAfterMailFrom
        case okAfterRecipient
        case okAfterDataCommand
        case okAfterMailData
        case okAfterQuit
        case nothing
        
        case error
    }
    
    private var currentlyWaitingFor = Expect.initialMessageFromServer
    private let email: Email
    private let serverConfiguration: ServerConfiguration
    private let allDonePromise: EventLoopPromise<Void>
    
    init(configuration: ServerConfiguration, email: Email, allDonePromise: EventLoopPromise<Void>) {
        self.email = email
        self.allDonePromise = allDonePromise
        self.serverConfiguration = configuration
    }
    
    func send(context: ChannelHandlerContext, command: SMTPRequest) {
        context.writeAndFlush(self.wrapOutboundOut(command)).cascadeFailure(to: self.allDonePromise)
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let result = self.unwrapInboundIn(data)
        switch result {
        case .error(let message):
            self.allDonePromise.fail(NSError(domain: "sending email", code: 1, userInfo: ["reason": message]))
            return
        case .ok:
            () // cool
        }

        switch self.currentlyWaitingFor {
        case .initialMessageFromServer:
            self.send(context: context, command: .sayHello(serverName: self.serverConfiguration.hostname))
            self.currentlyWaitingFor = .okForOurHello
        case .okForOurHello:
            self.send(context: context, command: .beginAuthentication)
            self.currentlyWaitingFor = .okForOurAuthBegin
        case .okForOurAuthBegin:
            self.send(context: context, command: .authUser(self.serverConfiguration.username))
            self.currentlyWaitingFor = .okAfterUsername
        case .okAfterUsername:
            self.send(context: context, command: .authPassword(self.serverConfiguration.password))
            self.currentlyWaitingFor = .okAfterPassword
        case .okAfterPassword:
            self.send(context: context, command: .mailFrom(self.email.senderEmail))
            self.currentlyWaitingFor = .okAfterMailFrom
        case .okAfterMailFrom:
            self.send(context: context, command: .recipient(self.email.recipientEmail))
            self.currentlyWaitingFor = .okAfterRecipient
        case .okAfterRecipient:
            self.send(context: context, command: .data)
            self.currentlyWaitingFor = .okAfterDataCommand
        case .okAfterDataCommand:
            self.send(context: context, command: .transferData(email))
            self.currentlyWaitingFor = .okAfterMailData
        case .okAfterMailData:
            self.send(context: context, command: .quit)
            self.currentlyWaitingFor = .okAfterQuit
        case .okAfterQuit:
            context.close(promise: self.allDonePromise)
            self.currentlyWaitingFor = .nothing
        case .nothing:
            () // ignoring more data whilst quit (it's odd though)
        case .error:
            fatalError("error state")
        }
    }
}
