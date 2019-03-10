import metric

type
  Collector* = ref object of RootObj

method collect*(self: Collector): seq[MetricFamilySamples] {.base.} =
  doAssert false