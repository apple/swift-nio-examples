# NIOSMTP

NIOSMTP is a demo app that is a very simple SMTP client and therefore allows you to send email. NIOSMTP is an iOS 12 app that uses [`swift-nio-transport-services`](https://github.com/apple/swift-nio-transport-services) on top of [`Network.framework`](https://developer.apple.com/documentation/network) to do all the networking.

## Prerequisites

- Xcode 10+
- CocoaPods

## Caveats

- before trying out the app you need to configure your SMTP server in `NIOSMTP/Configuration.swift`
- `STARTTLS` is not supported at this point so the server will need to support `SMTPS`
- it's a very basic SMTP/MIME implementation, the email body isn't even base64 encoded neither is any other data.
- The `SendEmailHandler` should accept `Email` objects through the pipeline to be more widely usable. Currently it requires the `Email` object in its initialiser which means it can only ever send one email per connection (`Channel`)
