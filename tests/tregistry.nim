#
# To run these tests, simply execute `nimble test`.
import unittest
import times
import strutils

import prometheus

suite "tregistry":
  setup:
    let testRegistry = newCollectorRegistry()

  test "simple":
    var c = newGauge(
      "my_inprogress_requests",
      "Description of gauge",
      registry=testRegistry
    )
    c.inc(255)

    let exposition = testRegistry.generateLatest()
    const expected = """
      # HELP my_inprogress_requests Description of gauge
      # TYPE my_inprogress_requests gauge
      my_inprogress_requests 255.0
    """.unindent()
    check exposition == expected

  test "labels":
    var c = newGauge(
      "my_inprogress_requests",
      "My cool gauge",
      @["Page", "Method"],
      registry=testRegistry
    )
    c.inc(123)
    c.labels("/", "GET").set(123.45)
    c.labels("/", "POST").set(1)

    let exposition = testRegistry.generateLatest()
    const expected = """
      # HELP my_inprogress_requests My cool gauge
      # TYPE my_inprogress_requests gauge
      my_inprogress_requests{Method="GET",Page="/"} 123.45
      my_inprogress_requests{Method="POST",Page="/"} 1.0
      my_inprogress_requests 123.0
    """.unindent()
    check exposition == expected