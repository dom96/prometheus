import prometheus/[registry, metric, collector]

type
  GCCollector* = ref object of Collector

proc newGCCollector*(registry = globalRegistry): GCCollector =
  result = GCCollector()
  registry.register(result)

method collect*(self: GCCollector): seq[MetricFamilySamples] =
  # Gather GC stats
  var freeMemoryGauge = initMetricFamilySamples(
    "nim_gc_mem_free",
    MetricType.Gauge,
    "Number of bytes that are owned by the process, but do not hold any meaningful data.",
    Unit.Bytes
  )

  var totalMemoryGauge = initMetricFamilySamples(
    "nim_gc_mem_total",
    MetricType.Gauge,
    "Total number of bytes that are owned by the process",
    Unit.Bytes
  )

  var occupiedMemoryGauge = initMetricFamilySamples(
    "nim_gc_mem_occupied",
    MetricType.Gauge,
    "Total number of bytes that are held by the allocator",
    Unit.Bytes
  )

  var maxMemoryGauge = initMetricFamilySamples(
    "nim_gc_mem_max",
    MetricType.Gauge,
    "Maximum number of bytes allocated by the process across its whole run time",
    Unit.Bytes
  )

  freeMemoryGauge.addMetric(getFreeMem())
  totalMemoryGauge.addMetric(getTotalMem())
  occupiedMemoryGauge.addMetric(getOccupiedMem())
  maxMemoryGauge.addMetric(getMaxMem())

  result = @[
    freeMemoryGauge, totalMemoryGauge, occupiedMemoryGauge, maxMemoryGauge
  ]

  when defined(nimTypeNames):
    var typeHeapUsageGauge = initMetricFamilySamples(
      "nim_gc_mem_object_usage",
      MetricType.Gauge,
      "Total number of bytes allocated for objects of a certain type",
      Unit.Bytes
    )

    var typeAllocCountGauge = initMetricFamilySamples(
      "nim_gc_mem_object_count",
      MetricType.Gauge,
      "Total count of allocated objects of a certain type",
      Unit.Unspecified
    )

    var allocCountGauge = initMetricFamilySamples(
      "nim_gc_allocs",
      MetricType.Gauge,
      "Total count of allocations performed by the GC",
      Unit.Unspecified
    )

    var deallocCountGauge = initMetricFamilySamples(
      "nim_gc_deallocs",
      MetricType.Gauge,
      "Total count of deallocations performed by the GC",
      Unit.Unspecified
    )

    # Based on gc_common.dumpNumberOfInstances
    type InstancesInfo = array[400, (cstring, int, int)]
    var a: InstancesInfo
    var n = 0
    var totalAllocated = 0
    for it in dumpHeapInstances():
      a[n] = it
      inc n
      inc totalAllocated, it.sizes

    for i in 0 .. n-1:
      typeHeapUsageGauge.addMetric(a[i][2], labels={"type": $a[i][0]})
      typeAllocCountGauge.addMetric(a[i][1], labels={"type": $a[i][0]})
    typeHeapUsageGauge.addMetric(totalAllocated)
    let (allocs, deallocs) = getMemCounters()
    allocCountGauge.addMetric(allocs)
    deallocCountGauge.addMetric(deallocs)

    result.add(@[
      typeHeapUsageGauge, typeAllocCountGauge, allocCountGauge, deallocCountGauge
    ])



var globalGCCollector* = newGCCollector()