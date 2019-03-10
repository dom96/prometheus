#
# To run these tests, simply execute `nimble test`.
import unittest
import times

import prometheus
test "simple gauge":
  var c = newGauge(
    "my_inprogress_requests",
    "Description of gauge"
  )

  c.inc()
  c.dec(10)

  block:
    let samples = getMultiSamples(c)
    for sample in samples:
      if sample.suffix == "":
        check sample.value == -9.0

  c.set(4.2)
  block:
    let samples = getMultiSamples(c)
    for sample in samples:
      if sample.suffix == "":
        check sample.value == 4.2


test "labels gauge":
  var c = newGauge(
    "my_inprogress_requests",
    "Descr",
    @["method", "endpoint"]
  )

  c.labels("get", "/").inc(14)
  c.labels("post", "/").set(123)
  c.dec()
  let samples = getMultiSamples(c)
  for sample in samples:
    if sample.suffix == "":
      if sample.seriesLabels == {"method": "get", "endpoint": "/"}:
        check sample.value == 14.0
      elif sample.seriesLabels == {"method": "post", "endpoint": "/"}:
        check sample.value == 123.0
      else:
        check sample.value == -1.0