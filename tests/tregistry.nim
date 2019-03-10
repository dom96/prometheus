#
# To run these tests, simply execute `nimble test`.
import unittest
import times
import strutils

import prometheus
test "simple":
  var c = initGauge(
    "my_inprogress_requests",
    "Description of gauge"
  )
  c.inc(255)

  let exposition = generateLatest()
  const expected = """
    # HELP my_inprogress_requests Description of gauge
    # TYPE my_inprogress_requests gauge
    my_inprogress_requests 255.0""".unindent()
  check exposition == expected