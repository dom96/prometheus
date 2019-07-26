# Prometheus client library for Nim

This is a Nim client library for Prometheus. Features include:

* Multiple metric types:
  * Counters
  * Gauges
  * Histograms
* Nim-specific collectors:
  * [Async collector](https://github.com/dom96/prometheus/blob/master/src/prometheus/collectors/asynccollector.nim) (logs statistics about pending futures, timers and callbacks from Nim's async event loop)
  * [GC collector](https://github.com/dom96/prometheus/blob/master/src/prometheus/collectors/gccollector.nim) (logs heap allocation statistics, compile with `-d:nimTypeNames` to get granular information about the allocated object types)

## Usage

Add this into your .nimble file:

```
requires "prometheus"
```

## Testing

Run:

```
nimble test
```

## License

MIT
