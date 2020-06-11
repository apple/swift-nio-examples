# nio-launchd

This is an example of launching a NIO server using `launchd` on macOS.

First, create this file at ~/Library/LaunchAgents/io.swiftnio.nio-launchd.plist

```
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>Label</key><string>io.swiftnio.nio-launchd</string>
        <key>ProgramArguments</key>
        <array>
            <string>/path/to/nio-launchd</string>
            <string>server</string>
        </array>
        <key>WorkingDirectory</key><string>/tmp</string>
        <key>Sockets</key>
        <dict>
            <key>Listeners</key>
            <dict>
                <key>SockPathName</key>
                <string>/tmp/nio.launchd.sock</string>
            </dict>
        </dict>
    </dict>
</plist>
```

Load the plist using `launchctl` command:

```
$ launchctl load -w ~/Library/LaunchAgents/io.swiftnio.nio-launchd.plist
```

Finally, run the client to test the connection:

```
$ swift run nio-launchd client
```

You can stop and unload agent using these commands:

```
$ launchctl stop io.swiftnio.nio-launchd
$ launchctl unload -w ~/Library/LaunchAgents/io.swiftnio.nio-launchd.plist
```
