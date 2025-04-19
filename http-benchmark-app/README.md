# HTTPBenchmarkApp

A toy HTTP server and in‑process benchmark runner built on SwiftNIO.  
It provides a **consolidated benchmark mode** that executes four real‑world scenarios and prints percentile timing (p0, p25, p50, p75, p90, p99, p100).

---

## Requirements

- Swift 5.9+  
- macOS or Linux  
- (Optional) To enable io_uring: build with the `Network` package available.

---

## Building

```bash
git clone <repo>
cd http-benchmark-app
swift build -c release
```

---

## Running Consolidated Tests

```bash
.build/release/HTTPBenchmarkApp \
  [--use-io-uring] \
  --run-all-benchmarks \
  [--samples <N>]
```

### Flags

```bash
--run-all-benchmarks
Executes four scenarios—LargeFile, Concurrency, Partial IO, Lock Contention—and prints percentile tables.

--samples <N> (default: 10)
Number of iterations per scenario.

--use-io-uring
If built with NIOTransportServices, runs on NIOTSEventLoopGroup (Linux io_uring).
```
## Example

```bash
.build/release/HTTPBenchmarkApp --use-io-uring --run-all-benchmarks --samples 10
```

### Sample Output

```bash
Running consolidated benchmarks...

╒══════════════════════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╕
│ Metric                   │     p0  │    p25  │    p50  │    p75  │    p90  │    p99  │   p100  │ Samples │
╞══════════════════════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╡
│ LargeFile (ms)           │  170.72 │  178.06 │  179.18 │  188.18 │  192.89 │  192.89 │  196.11 │      10 │
╘══════════════════════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╛
╒══════════════════════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╕
│ Metric                   │     p0  │    p25  │    p50  │    p75  │    p90  │    p99  │   p100  │ Samples │
╞══════════════════════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╡
│ Concurrency (ms)         │  268.11 │  279.08 │  285.77 │  289.11 │  292.54 │  292.54 │  294.88 │      10 │
╘══════════════════════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╛
╒══════════════════════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╕
│ Metric                   │     p0  │    p25  │    p50  │    p75  │    p90  │    p99  │   p100  │ Samples │
╞══════════════════════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╡
│ Partial IO (ms)          │    0.01 │    0.01 │    0.01 │    0.01 │    0.02 │    0.02 │    0.24 │      10 │
╘══════════════════════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╛
╒══════════════════════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╤═════════╕
│ Metric                   │     p0  │    p25  │    p50  │    p75  │    p90  │    p99  │   p100  │ Samples │
╞══════════════════════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╪═════════╡
│ Lock Contention (ms)     │  270.85 │  277.18 │  279.32 │  279.79 │  288.83 │  288.83 │  295.96 │      10 │
╘══════════════════════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╧═════════╛
```

---

## Extension

To add new benchmark scenarios, invoke measureMultiple(iterations:block:) inside runConsolidatedBenchmarks(iterations:) and print via formatBenchmarkTable(metric:stats:)