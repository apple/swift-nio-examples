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

import UIKit
import NIO
import NIOExtras
import NIOTransportServices
import NIOTLS
import NIOSSL

#if canImport(Network)
import Network
#endif

func sendEmail(_ email: Email,
               group: EventLoopGroup,
               communicationHandler: @escaping (String) -> Void,
               queue: DispatchQueue,
               _ handler: @escaping (Error?) -> Void) {
    let emailSentPromise: EventLoopPromise<Void> = group.next().makePromise()

    let bootstrap: NIOClientTCPBootstrap
    do {
        bootstrap = try configureBootstrap(group: group,
                                           email: email,
                                           emailSentPromise: emailSentPromise,
                                           communicationHandler: communicationHandler)
    } catch {
        queue.async {
            handler(error)
        }
        return
    }

    let connection = bootstrap.connect(host: Configuration.shared.serverConfig.hostname,
                                       port: Configuration.shared.serverConfig.port)

    connection.cascadeFailure(to: emailSentPromise)
    emailSentPromise.futureResult.map {
        connection.whenSuccess { $0.close(promise: nil) }
        queue.async {
            handler(nil)
        }
    }.whenFailure { error in
        connection.whenSuccess { $0.close(promise: nil) }
        queue.async {
            handler(error)
        }
    }
}


class ViewController: UIViewController {
    var group: EventLoopGroup? = nil

    @IBOutlet weak var sendEmailButton: UIButton!
    @IBOutlet weak var logView: UITextView!
    @IBOutlet weak var textField: UITextView!
    @IBOutlet weak var subjectField: UITextField!
    @IBOutlet weak var toField: UITextField!
    @IBOutlet weak var fromField: UITextField!

    @IBAction func sendEmailAction(_ sender: UIButton) {
        self.logView.text = ""
        let email = Email(senderName: nil,
                          senderEmail: self.fromField.text!,
                          recipientName: nil,
                          recipientEmail: self.toField.text!,
                          subject: self.subjectField.text!,
                          body: self.textField.text!)
        let commHandler: (String) -> Void = { str in
            DispatchQueue.main.async {
                self.logView.text += str + "\n"
            }
        }
        sendEmail(email, group: self.group!, communicationHandler: commHandler, queue: DispatchQueue.main) { maybeError in
            assert(Thread.isMainThread)
            if let error = maybeError {
                self.sendEmailButton.titleLabel?.text = "❌"
                self.logView.text += "ERROR: \(error)\n"
            } else {
                self.sendEmailButton.titleLabel?.text = "✅"
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        let group = makeEventLoopGroup(loopCount: 1, implementation: .best)
        self.group = group
    }

    override func viewWillDisappear(_ animated: Bool) {
        try! self.group?.syncShutdownGracefully()
        self.group = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }
}

// MARK: - NIO/NIOTS handling

func makeNIOSMTPHandlers(communicationHandler: @escaping (String) -> Void,
                         email: Email,
                         emailSentPromise: EventLoopPromise<Void>) -> [ChannelHandler] {
    return [
        PrintEverythingHandler(handler: communicationHandler),
        ByteToMessageHandler(LineBasedFrameDecoder()),
        SMTPResponseDecoder(),
        MessageToByteHandler(SMTPRequestEncoder()),
        SendEmailHandler(configuration: Configuration.shared.serverConfig,
                         email: email,
                         allDonePromise: emailSentPromise)
    ]
}

private let sslContext = try! NIOSSLContext(configuration: TLSConfiguration.forClient())

func configureBootstrap(group: EventLoopGroup,
                        email: Email,
                        emailSentPromise: EventLoopPromise<Void>,
                        communicationHandler: @escaping (String) -> Void) throws -> NIOClientTCPBootstrap {
    let hostname = Configuration.shared.serverConfig.hostname
    let bootstrap: NIOClientTCPBootstrap

    switch (NetworkImplementation.best, Configuration.shared.serverConfig.tlsConfiguration) {
    case (.transportServices, .regularTLS), (.transportServices, .insecureNoTLS):
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
            bootstrap = NIOClientTCPBootstrap(NIOTSConnectionBootstrap(group: group),
                                              tls: NIOTSClientTLSProvider())
        } else {
            fatalError("Network.framework unsupported on this OS yet it was selected as the best option.")
        }
    case (.transportServices, .startTLS):
        if #available(macOS 10.14, iOS 12, tvOS 12, watchOS 3, *) {
            bootstrap = try NIOClientTCPBootstrap(NIOTSConnectionBootstrap(group: group),
                                                  tls: NIOSSLClientTLSProvider(context: sslContext,
                                                                               serverHostname: hostname))
        } else {
            fatalError("Network.framework unsupported on this OS yet it was selected as the best option.")
        }
    case (.posix, _):
        bootstrap = try NIOClientTCPBootstrap(ClientBootstrap(group: group),
                                              tls: NIOSSLClientTLSProvider(context: sslContext,
                                                                           serverHostname: hostname))
    }

    switch Configuration.shared.serverConfig.tlsConfiguration {
    case .regularTLS:
        bootstrap.enableTLS()
    case .insecureNoTLS, .startTLS:
        () // no TLS to start with
    }

    return bootstrap.channelInitializer { channel in
        channel.pipeline.addHandlers(makeNIOSMTPHandlers(communicationHandler: communicationHandler,
                                                         email: email,
                                                         emailSentPromise: emailSentPromise))
    }
}

/// Network implementation and by extension which version of NIO to use.
enum NetworkImplementation {
    /// POSIX sockets and NIO.
    case posix

    /// NIOTransportServices (and Network.framework).
    case transportServices

    /// Return the best implementation available for this platform, that is NIOTransportServices
    /// when it is available or POSIX and NIO otherwise.
    static var best: NetworkImplementation {
        if #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) {
            return .transportServices
        } else {
            return .posix
        }
    }
}

/// Makes an appropriate `EventLoopGroup` based on the given implementation.
///
/// For `.posix` this is a `MultiThreadedEventLoopGroup`, for `.networkFramework` it is a
/// `NIOTSEventLoopGroup`.
///
/// - Parameter implementation: The network implementation to use.
func makeEventLoopGroup(loopCount: Int, implementation: NetworkImplementation) -> EventLoopGroup {
    switch implementation {
    case .transportServices:
        guard #available(OSX 10.14, iOS 12.0, tvOS 12.0, watchOS 6.0, *) else {
            // This is gated by the availability of `.networkFramework` so should never happen.
            fatalError(".networkFramework is being used on an unsupported platform")
        }
        return NIOTSEventLoopGroup(loopCount: loopCount, defaultQoS: .utility)
    case .posix:
        return MultiThreadedEventLoopGroup(numberOfThreads: loopCount)
    }
}
