import metric

type
  Collector* = ref object of RootObj

# method collect*(self: Collector): seq[Metric] {.base.} =
#   doAssert false
