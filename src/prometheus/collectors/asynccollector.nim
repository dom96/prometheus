import asyncdispatch
when isFutureLoggingEnabled:
  import options, tables, deques, heapqueue

  import prometheus/[registry, metric, collector]

  type
    AsyncCollector* = ref object of Collector

  proc newAsyncCollector*(registry = globalRegistry): AsyncCollector =
    result = AsyncCollector()
    registry.register(result)

  proc getCreationLocation(info: FutureInfo): Option[StackTraceEntry] =
    for entry in info.stackTrace:
      if entry.procname == info.fromProc:
        # The trace closest to the end should give us the most likely location
        # of where this future was created.
        result = some(entry)

  method collect*(self: AsyncCollector): seq[MetricFamilySamples] =
    # Gather async stats
    var pendingFuturesGauge = initMetricFamilySamples(
      "nim_async_pending_futures",
      MetricType.Gauge,
      "Number of futures currently pending.",
      Unit.Unspecified
    )

    var pendingCallbacksGauge = initMetricFamilySamples(
      "nim_async_dispatcher_pending_callbacks",
      MetricType.Gauge,
      "Number of callbacks in the dispatcher still waiting to be processed.",
      Unit.Unspecified
    )

    var pendingTimersGauge = initMetricFamilySamples(
      "nim_async_dispatcher_pending_timers",
      MetricType.Gauge,
      "Number of timers in the dispatcher still waiting to be processed.",
      Unit.Unspecified
    )

    let inProgress = getFuturesInProgress()
    var totalPendingFutures = 0
    for info, count in inProgress:
      totalPendingFutures.inc(count)
      let creation = getCreationLocation(info)
      if creation.isSome():
        let entry = creation.get()
        pendingFuturesGauge.addMetric(
          count,
          labels={
            "procName": $entry.procname,
            "line": $entry.line,
            "filename": $entry.filename
          },
          merge=true
        )
      else:
        pendingFuturesGauge.addMetric(
          count,
          labels={
            "procName": info.fromProc,
            "line": "unknown",
            "filename": "unknown"
          },
          merge=true
        )
    pendingFuturesGauge.addMetric(totalPendingFutures)

    pendingCallbacksGauge.addMetric(getGlobalDispatcher().callbacks.len)
    pendingTimersGauge.addMetric(getGlobalDispatcher().timers.len)

    result = @[
      pendingFuturesGauge, pendingCallbacksGauge, pendingTimersGauge
    ]

  var globalAsyncCollector* = newAsyncCollector()