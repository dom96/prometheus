#
# To run these tests, simply execute `nimble test`.
import unittest
import times

import prometheus
test "simple counter":
  var c = initCounter(
    "my_requests_total",
    "HTTP Failures"
  )

  c.inc()
  c.inc(25.0)
  let samples = getMultiSamples(c)
  for sample in samples:
    if sample.suffix == "_total":
      check sample.value == 26.0

test "counter with labels":
  var c = initCounter(
    "my_requests_total",
    "HTTP Failures",
    @["method", "endpoint"]
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
  var c = initCounter(
    "my_requests_total",
    "HTTP Failures"
  )

  expect ValueError:
    c.inc(-1)