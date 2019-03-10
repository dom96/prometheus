#
# To run these tests, simply execute `nimble test`.
import unittest
import times

import prometheus

suite "tcounter":
  setup:
    let testRegistry = newCollectorRegistry()

  test "simple counter":
    var c = newCounter(
      "my_requests_total",
      "HTTP Failures",
      registry=testRegistry
    )

    c.inc()
    c.inc(25.0)
    let samples = getMultiSamples(c)
    for sample in samples:
      if sample.suffix == "_total":
        check sample.value == 26.0

  test "counter with labels":
    var c = newCounter(
      "my_requests_total",
      "HTTP Failures",
      @["method", "endpoint"],
      registry=testRegistry
    )

    c.labels("get", "/").inc(25)
    c.inc()
    let samples = getMultiSamples(c)
    for sample in samples:
      if sample.suffix == "_total":
        if sample.seriesLabels == {"method": "get", "endpoint": "/"}:
          check sample.value == 25.0
        else:
          check sample.value == 1

  test "counter cannot be decremented":
    var c = newCounter(
      "my_requests_total",
      "HTTP Failures",
      registry=testRegistry
    )

    expect ValueError:
      c.inc(-1)

# TODO: Verify label names