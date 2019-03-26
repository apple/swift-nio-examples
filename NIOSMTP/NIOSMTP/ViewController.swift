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
import NIOTransportServices

import Network

func sendEmail(_ email: Email,
               group: NIOTSEventLoopGroup,
               communicationHandler: @escaping (String) -> Void,
               _ handler: @escaping (Error?) -> Void) {
    let emailSentPromise: EventLoopPromise<Void> = group.next().makePromise()
    let configuration = NIOTSConnectionBootstrap.config

    let connection = NIOTSConnectionBootstrap(group: group)
        .channelInitializer { channel in
            channel.pipeline.addHandlers([
                PrintEverythingHandler(handler: communicationHandler),
                ByteToMessageHandler(LineBasedFrameDecoder()),
                SMTPResponseDecoder(),
                MessageToByteHandler(SMTPRequestEncoder()),
                SendEmailHandler(configuration: configuration,
                                 email: email,
                                 allDonePromise: emailSentPromise)
                ], position: .last)
        }
        .tlsConfig()
        .connect(host: configuration.hostname,
                 port: configuration.port)
    connection.cascadeFailure(to: emailSentPromise)
    emailSentPromise.futureResult.map {
        connection.whenSuccess { $0.close(promise: nil) }
        handler(nil)
    }.whenFailure { error in
        connection.whenSuccess { $0.close(promise: nil) }
        handler(error)
    }
}


class ViewController: UIViewController {

    var group: NIOTSEventLoopGroup? = nil

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
        sendEmail(email, group: self.group!, communicationHandler: commHandler) { maybeError in
            DispatchQueue.main.async {
                if let error = maybeError {
                    self.sendEmailButton.titleLabel?.text = "❌"
                    self.logView.text += "ERROR: \(error)\n"
                } else {
                    self.sendEmailButton.titleLabel?.text = "✅"
                }
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        let group = NIOTSEventLoopGroup(loopCount: 1, defaultQoS: .utility)
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

