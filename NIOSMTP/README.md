# NIOSMTP

NIOSMTP is a demo app that is a very simple SMTP client and therefore allows you to send email. NIOSMTP is an iOS 12 app that uses [`swift-nio-transport-services`](https://github.com/apple/swift-nio-transport-services) on top of [`Network.framework`](https://developer.apple.com/documentation/network) to do all the networking. It supports plain text SMTP (boo), SMTPS, as well as SMTP with STARTTLS which is probably what your mail provider wants.

## Prerequisites

- Xcode 11+

## Caveats

- if you want to try this out you'll have to put your SMTP server configuration
  in [`Configuration.swift`](https://github.com/apple/swift-nio-examples/blob/main/NIOSMTP/NIOSMTP/Configuration.swift), there's no configuration UI at this moment
- before trying out the app you need to configure your SMTP server in `NIOSMTP/Configuration.swift`
- it's a very basic SMTP/MIME implementation, the email body isn't even base64 encoded neither is any other data.
- The `SendEmailHandler` should accept `Email` objects through the pipeline to be more widely usable. Currently it requires the `Email` object in its initialiser which means it can only ever send one email per connection (`Channel`)

## Screenshots

<img width="418" alt="main screen" src="https://user-images.githubusercontent.com/624238/45869756-2987da00-bd81-11e8-8a35-732d050eb44a.png">
<img width="422" alt="email sent" src="https://user-images.githubusercontent.com/624238/45869764-2d1b6100-bd81-11e8-8082-d7bc43e0b05b.png">
