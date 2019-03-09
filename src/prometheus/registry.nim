import collector

type
  CollectorRegistry* = ref object
    collectors: seq[Collector]

proc newCollectorRegistry*(): CollectorRegistry =
  CollectorRegistry(
    collectors: @[]
  )

var
  globalRegistry* = newCollectorRegistry()

proc register*(self: CollectorRegistry, collector: Collector) =
  ## Add a collector to the registry.
  self.collectors.add(collector)