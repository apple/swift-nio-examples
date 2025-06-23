# HTTP Responsiveness Server

This HTTP server offers a simple API that allows load testing, based on [`SimpleResponsivenessRequestMux`](https://github.com/apple/swift-nio-extras/blob/main/Sources/NIOHTTPResponsiveness/SimpleResponsivenessRequestMux.swift). It implements the following endpoints:

 - GET `/responsiveness`: Returns an overview of the responsiveness enpoints.
 - GET `/responsiveness/download/{size}`: Download `size` bytes of data.
 - POST `/responsiveness/upload`: Upload data.
 - GET `/drip`: Provides a stream of zeroes.
 - POST `/admin/shutdown`: Gracefully shutdown the server. 

```
USAGE: http-responsiveness-server --host <host> --port <port> [--threads <threads>] [--max-idle-time <max-idle-time>] [--max-age <max-age>] [--max-grace-time <max-grace-time>]

OPTIONS:
  --host <host>           Which host to bind to.
  --port <port>           Which port to bind to.
  --threads <threads>     Override how many threads to use.
  --max-idle-time <max-idle-time>
                          Time a connection may be idle for before being closed, in seconds.
  --max-age <max-age>     Time a connection may exist before being gracefully closed, in seconds.
  --max-grace-time <max-grace-time>
                          Grace period for connections to close after shutdown, in seconds.
  -h, --help              Show help information.
```

## Example execution

Run the server in one terminal:

```bash
swift run HTTPResponsivenessServer --host 127.0.0.1 --port 2345
```

Make requests from a separate terminal, e.g., a download process:

```bash
curl --http2-prior-knowledge -o /dev/null http://127.0.0.1:2345/responsiveness/download/8000000000
```

Gracefully shutdown the server:

```bash
curl -X POST --http2-prior-knowledge -o data.bin http://127.0.0.1:2345/admin/shutdown
```

Don't forget to use `swift run -c release` for any measurements!
