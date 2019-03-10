import strutils, strformat, algorithm

import collector, metric

type
  CollectorRegistry* = ref object
    collectors: seq[Collector]
    counters: seq[Counter]
    gauges: seq[Gauge]

proc newCollectorRegistry*(): CollectorRegistry =
  CollectorRegistry(
    collectors: @[]
  )

# TODO: Use shared memory + getGlobalRegistry proc (and/or template for locking)
var
  globalRegistry* = newCollectorRegistry()

proc register*(self: CollectorRegistry, collector: Collector) =
  ## Add a collector to the registry.
  self.collectors.add(collector)

proc register*(self: CollectorRegistry, counter: Counter) =
  ## Add a counter to the registry.
  self.counters.add(counter)

proc register*(self: CollectorRegistry, gauge: Gauge) =
  ## Add a gauge to the registry.
  self.gauges.add(gauge)

iterator collect*(self: CollectorRegistry): MetricFamilySamples =
  # TODO LOCK
  for collector in self.collectors:
    for metric in collector.collect():
      yield metric

  for metric in self.counters:
    for sample in metric.collect():
      yield sample

  for metric in self.gauges:
    for sample in metric.collect():
      yield sample

proc escapeDoc(doc: string): string =
  doc.multireplace({"\\": r"\\", "\n": r"\n"})

proc escapeLabel(labelVal: string): string =
  labelVal.multireplace({"\\": r"\\", "\n": r"\n", "\"": "\\\""})

proc generateSample(sample: Sample, output: var string) =
  output.add(sample.name)

  let labels = sample.seriesLabels.sortedByIt(it[0])
  if labels.len > 0:
    output.add("{")
  for i in 0 ..< labels.len:
    if i != 0:
      output.add(",")
    let label = labels[i]
    output.add(label[0])
    output.add("=\"")
    output.add(escapeLabel(label[1]))
    output.add("\"")

  if labels.len > 0:
    output.add("}")

  output.add(" ")
  # Other languages use a custom float to string implementation, but I think
  # Nim's is compatible with Go's ParseFloat.
  output.add($sample.value)

  # TODO: Timestamp?
  output.add("\n")

proc generateLatest*(registry = globalRegistry): string =
  for metric in registry.collect():
    result.add(
      fmt("# HELP {metric.name} {escapeDoc(metric.documentation)}\n")
    )
    result.add(fmt("# TYPE {metric.name} {toLower($metric.kind)}\n"))
    for sample in metric.samples:
      generateSample(sample, result)


# -- This duplication isn't the best, but it does solve some problems.
proc newCounter*(
  name: string, documentation: string,
  labelNames: seq[string] = @[],
  namespace = "",
  unit = Unit.Unspecified,
  registry = globalRegistry,
  labelValues: seq[string] = @[]
): Counter =
  result = newCounterOnly(
    name,
    documentation,
    labelNames,
    namespace,
    unit,
    labelValues
  )

  if labelValues.len == 0:
    registry.register(result)

proc newGauge*(
  name: string, documentation: string,
  labelNames: seq[string] = @[],
  namespace = "",
  unit = Unit.Unspecified,
  registry = globalRegistry,
  labelValues: seq[string] = @[]
): Gauge =
  result = newGaugeOnly(
    name,
    documentation,
    labelNames,
    namespace,
    unit,
    labelValues
  )

  if labelValues.len == 0:
    registry.register(result)