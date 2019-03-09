import tables, sets, sequtils, times, strformat, macros

import registry

type
  Sample* =
    tuple[suffix: string, seriesLabels: seq[(string, string)], value: float64]

type
  ## https://prometheus.io/docs/practices/naming/
  Unit* = enum
    Unspecified, Seconds, Celsius, Meters, Bytes, Ratio, Volts, Amperes, Joules,
    Grams

  MetricBase* = object
    name: string
    documentation: string
    labelNames: seq[string]
    labelValues: seq[string]
    namespace: string
    unit: Unit
    registry: CollectorRegistry

proc initMetricBase(
  name: string,
  documentation: string,
  labelNames: seq[string],
  namespace: string,
  unit: Unit,
  registry: CollectorRegistry,
  labelValues: seq[string]
): MetricBase =
  MetricBase(
    name: name,
    documentation: documentation,
    labelNames: labelNames,
    labelValues: labelValues,
    namespace: namespace,
    unit: unit,
    registry: registry
  )

proc getMultiSamples[T](self: T): seq[Sample] =
  # TODO: Multi-threading: lock (https://bit.ly/2VHhm5Z)
  for labels, metric in pairs(self.children):
    let seriesLabels = zip(self.base.labelNames, labels)
    for sample in metric.getMultiSamples():
      result.add(
        (
          sample.suffix,
          seriesLabels & sample.seriesLabels,
          sample.value
        )
      )

  result.add(self.getSelfSamples())

macro initMetric[T](self: T, labelValues: varargs[string]): T =
  let t = getTypeInst(self)
  let initCall = newIdentNode("init" & $t)
  result = quote:
    `initCall`(
      self.base.name,
      self.base.documentation,
      self.base.labelNames,
      self.base.namespace,
      self.base.unit,
      self.base.registry,
      @labelValues
    )

proc labels*[T](self: var T, labelValues: varargs[string]): var T =
  if self.base.labelNames.len == 0:
    raise newException(
      ValueError, "No label names were set when constructing " & self.base.name
    )

  if self.base.labelValues.len != 0:
    raise newException(
      ValueError,
      fmt(
        "{self.base.name} already has labels set " &
        "({self.base.labelValues}); can not chain calls to .labels()"
      )
    )

  if labelValues.len != self.base.labelNames.len:
    raise newException(ValueError, fmt"Incorrect label count")

  # TODO: Thread lock
  if @labelValues notin self.children:
    self.children[@labelValues] = initMetric(self, labelValues)
  return self.children[@labelValues]

proc remove*[T](self: var T, labelValues: varargs[string]) =
  if self.base.labelNames.len == 0:
    raise newException(
      ValueError,
      fmt"No label names were set when constructing {self.base.labelNames}"
    )

  if labelValues.len != self.base.labelNames.len:
    raise newException(
      ValueError, fmt"Incorrect label count for {self.base.labelNames}"
    )

  # TODO: Lock
  self.children.del(@labelValues)

proc initSample(
  suffix: string, seriesLabels: seq[(string, string)], value: float64
): Sample =
  return (suffix, seriesLabels, value)

type
  Counter* = object
    base: MetricBase
    children: Table[seq[string], Counter] # Label values -> MetricBase
    value: float64
    created: float64

proc getSelfSamples(self: Counter): seq[Sample] =
  # https://bit.ly/2VILoGA
  return @[
    initSample("_total", @[], self.value),
    initSample("_created", @[], self.value)
  ]

proc reset*(self: var Counter) =
  self.value = float64(0)
  self.created = epochTime()

proc inc*(self: var Counter, amount=1.0) =
  self.value += amount

proc initCounter*(
  name: string, documentation: string,
  labelNames: seq[string] = @[],
  namespace = "",
  unit = Unit.Unspecified,
  registry = registry.globalRegistry,
  labelValues: seq[string] = @[]
): Counter =
  result =
    Counter(
      base: initMetricBase(
        name, documentation, labelNames, namespace, unit, registry, labelValues
      ),
      created: epochTime(),
    )
  if labelValues.len == 0:
    result.children = initTable[seq[string], Counter]()

when isMainModule:
  # Let's test this architecture.
  var c = initCounter(
    "my_requests_total",
    "HTTP Failures",
    @["method", "endpoint"]
  )

  c.labels("get", "/").inc()
  c.inc()

  for sample in getMultiSamples(c):
    echo sample