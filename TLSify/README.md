# TLSify

TLSify is a simple TLS proxy. It accepts plaintext (unencrypted) connections and TLS-wraps them to a target.

This functionality can be very useful if you want to use Wireshark, `tcpdump`, or similar tools to snoop on traffic whilst still having everything
that leaves your machine fully encrypted.

## Example

First, get three terminal windows ready.

Run this in the first window:

```
swift run -c release TLSify 8080 httpbin.org 443
```

Then, in the second one run

```
sudo tcpdump -i lo0 -A '' 'port 8080'
```

and finally, in the third you can kick off a `curl`:

```
curl -H "host: httpbin.org" http://localhost:8080/anything
```

The output from `curl` will look something like

```
{
  "args": {}, 
  "data": "", 
  "files": {}, 
  "form": {}, 
  "headers": {
    "Accept": "*/*", 
    "Host": "httpbin.org", 
    "User-Agent": "curl/7.64.1", 
    "X-Amzn-Trace-Id": "Root=1-5ec8fe25-2847b5847f049b288f87e72e"
  }, 
  "json": null, 
  "method": "GET", 
  "origin": "213.1.9.208", 
  "url": "https://httpbin.org/anything"
}
```

As you can see, `httpbin.org` says `"url": "https://httpbin.org/anything"` so it came encrypted. But the `tcpdump` should output
(amongst many other things) something like

```
11:45:46.650625 IP6 localhost.50297 > localhost.http-alt: Flags [P.], seq 1:84, ack 1, win 6371, options [nop,nop,TS val 855170339 ecr 855170339], length 83: HTTP: GET /anything HTTP/1.1
`.h..s.@.................................y...~..Y........{.....
2..#2..#GET /anything HTTP/1.1
Host: httpbin.org
User-Agent: curl/7.64.1
Accept: */*


11:45:46.650638 IP6 localhost.http-alt > localhost.50297: Flags [.], ack 84, win 6370, options [nop,nop,TS val 855170339 ecr 855170339], length 0
`.#.. .@...................................yY....~.......(.....
2..#2..#
11:45:47.021538 IP6 localhost.http-alt > localhost.50297: Flags [P.], seq 1:572, ack 84, win 6370, options [nop,nop,TS val 855170706 ecr 855170339], length 571: HTTP: HTTP/1.1 200 OK
`.#..[.@...................................yY....~.......c.....
2...2..#HTTP/1.1 200 OK
Date: Sat, 23 May 2020 10:46:41 GMT
Content-Type: application/json
Content-Length: 341
Connection: keep-alive
Server: gunicorn/19.9.0
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true

{
  "args": {}, 
  "data": "", 
  "files": {}, 
  "form": {}, 
  "headers": {
    "Accept": "*/*", 
    "Host": "httpbin.org", 
    "User-Agent": "curl/7.64.1", 
    "X-Amzn-Trace-Id": "Root=1-5ec8ff11-f8495d1407f5ace02a4251fc"
  }, 
  "json": null, 
  "method": "GET", 
  "origin": "213.1.9.208", 
  "url": "https://httpbin.org/anything"
}
```

where you can see both request and response in plain text :).
