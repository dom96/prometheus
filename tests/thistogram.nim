#
# To run these tests, simply execute `nimble test`.
import unittest
import times
import os
import strutils

import prometheus

suite "thistogram":
  setup:
    let testRegistry = newCollectorRegistry()

  test "simple histogram":
    var c = newHistogram(
      "func_latency",
      "Description of histogram",
      registry=testRegistry,
      unit=Unit.Seconds,
      buckets = @[
        0.005, 0.01, 0.025, 0.05, 0.075,
        0.1, 0.25, 0.5, 0.75, 1.0, 2.5,
        5.0, 7.5, 10.0, INF
      ]
    )

    c.observe(0.1)
    c.observe(0.5)
    c.observe(0.1)
    c.observe(0.5)

    block:
      let samples = getMultiSamples(c)
      for sample in samples:
        if sample.suffix == "_bucket":
          check sample.seriesLabels[0][0] == "le"
          case sample.seriesLabels[0][1]
          of "0.005", "0.01", "0.025", "0.05", "0.075":
            check sample.value == 0.0
          of "0.1", "0.25":
            check sample.value == 2.0
          else:
            check sample.value == 4.0
        if sample.suffix == "_sum":
          check sample.value == 1.2
        if sample.suffix == "_count":
          check sample.value == 4.0

  test "histogram with labels":
    var c = newHistogram(
      "func_latency",
      "Description of histogram",
      @["func", "endpoint"],
      registry=testRegistry,
      unit=Unit.Seconds,
      buckets = @[
        0.005, 0.01, 0.025, 0.05, 0.075,
        0.1, 0.25, 0.5, 0.75, 1.0, 2.5,
        5.0, 7.5, 10.0, INF
      ]
    )

    c.labels("myCoolFunc", "/").observe(0.05)
    c.labels("mySlowFunc", "/sleep").observe(1)
    c.labels("myCoolFunc", "/").observe(0.8)
    c.labels("myCoolFunc", "/").observe(0.065)
    c.labels("mySlowFunc", "/sleep").observe(1.123)

    block:
      let samples = getMultiSamples(c)
      var labelCount = 0
      for sample in samples:
        if sample.suffix == "_bucket":
          if sample.seriesLabels == @[("func", "myCoolFunc"), ("endpoint", "/"), ("le", "0.05")]:
            check sample.value == 1.0
            labelCount.inc
          if sample.seriesLabels == @[("func", "myCoolFunc"), ("endpoint", "/"), ("le", "1.0")]:
            check sample.value == 3.0
            labelCount.inc
          if sample.seriesLabels == @[("func", "mySlowFunc"), ("endpoint", "/sleep"), ("le", "2.5")]:
            check sample.value == 2.0
            labelCount.inc
        if sample.suffix == "_sum" and sample.seriesLabels.len == 0:
          check sample.value == 0
        if sample.suffix == "_count" and sample.seriesLabels.len == 0:
          check sample.value == 0

      check labelCount == 3

  test "histogram.time()":
    var c = newHistogram(
      "code_latency",
      "Description of histogram",
      registry=testRegistry,
      unit=Unit.Seconds,
      buckets = @[
        0.005, 0.01, 0.025, 0.05, 0.075,
        0.1, 0.25, 0.5, 0.75, 1.0, 2.5,
        5.0, 7.5, 10.0, INF
      ]
    )

    var count = 3
    for i in 0 ..< count:
      c.time:
        sleep(125)

    let samples = getMultiSamples(c)
    var hadValue = false
    for sample in samples:
      if sample.suffix == "_bucket":
        check sample.seriesLabels[0][0] == "le"
        case sample.seriesLabels[0][1]
        of "0.005", "0.01", "0.025", "0.05", "0.075", "0.1":
          check sample.value == 0.0
        else:
          check sample.value == count.float
          hadValue = true
      if sample.suffix == "_count":
        check sample.value == count.float
    check hadValue

    let latest = testRegistry.generateLatest()
    check r"code_latency_seconds_bucket{le=""inf""} 3.0" in latest