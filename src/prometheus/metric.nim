import tables, sets, sequtils, times, strformat, macros

type
  MetricSample* =
    tuple[suffix: string, seriesLabels: seq[(string, string)], value: float64]

  Sample* =
    tuple[name: string, seriesLabels: seq[(string, string)], value: float64]

  ## https://prometheus.io/docs/practices/naming/
  Unit* = enum
    Unspecified, Seconds, Celsius, Meters, Bytes, Ratio, Volts, Amperes, Joules,
    Grams

  MetricType* {.pure.} = enum
    Counter, Gauge, Summary, Histogram

  MetricBase* = object
    name: string
    documentation: string
    labelNames: seq[string]
    labelValues: seq[string]
    namespace: string
    unit: Unit

  MetricFamilySamples* = object
    name*: string
    kind*: MetricType
    documentation*: string
    unit*: Unit
    samples*: seq[Sample]

proc initSample*(
  name: string, seriesLabels: seq[(string, string)], value: float64
): Sample =
  return (name, seriesLabels, value)

proc initMetricSample(
  suffix: string, seriesLabels: seq[(string, string)], value: float64
): MetricSample =
  return (suffix, seriesLabels, value)

proc initMetricBase(
  name: string,
  documentation: string,
  labelNames: seq[string],
  namespace: string,
  unit: Unit,
  labelValues: seq[string]
): MetricBase =
  MetricBase(
    name: name,
    documentation: documentation,
    labelNames: labelNames,
    labelValues: labelValues,
    namespace: namespace,
    unit: unit
  )

# proc getSelfSamples[T](self: T): seq[Sample]
proc getMultiSamples*[T](self: T): seq[MetricSample] =
  # TODO: Maybe don't export this? It's only needed for tests.
  # TODO: Rewrite this to be an iterator.
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

  mixin getSelfSamples
  result.add(self.getSelfSamples())

macro initMetric[T](self: T, labelValues: varargs[string]): T =
  let t = getTypeInst(self)
  let newCall = newIdentNode("new" & $t & "Only")
  result = quote:
    `newCall`(
      self.base.name,
      self.base.documentation,
      self.base.labelNames,
      self.base.namespace,
      self.base.unit,
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

type
  Counter* = ref object
    base: MetricBase
    children: Table[seq[string], Counter] # Label values -> Counter
    value: float64
    created: float64

proc getSelfSamples*(self: Counter): seq[MetricSample] =
  # https://bit.ly/2VILoGA
  return @[
    initMetricSample("_total", @[], self.value),
    initMetricSample("_created", @[], self.created)
  ]

proc reset*(self: var Counter) =
  self.value = float64(0)
  self.created = epochTime()

proc inc*(self: var Counter, amount=1.0) =
  if amount < 0:
    raise newException(ValueError, "Cannot decrement a counter")
  self.value += amount

proc newCounterOnly*(
  name: string, documentation: string,
  labelNames: seq[string] = @[],
  namespace = "",
  unit = Unit.Unspecified,
  labelValues: seq[string] = @[]
): Counter =
  result =
    Counter(
      base: initMetricBase(
        name, documentation, labelNames, namespace, unit, labelValues
      ),
      created: epochTime(),
    )
  if labelValues.len == 0:
    result.children = initTable[seq[string], Counter]()

type
  Gauge* = ref object
    base: MetricBase
    children: Table[seq[string], Gauge] # Label values -> Gauge
    value: float64

proc getSelfSamples*(self: Gauge): seq[MetricSample] =
  return @[
    initMetricSample("", @[], self.value)
  ]

proc inc*(self: var Gauge, amount=1.0) =
  ## Increment gauge by the given amount.
  self.value += amount

proc dec*(self: var Gauge, amount=1.0) =
  ## Decrement gauge by the given amount.
  self.value -= amount

proc set*(self: var Gauge, value: float64) =
  ## Set gauge to the given value.
  self.value = value

proc setToCurrentTime*(self: var Gauge) =
  ## Set gauge to the current unixtime.
  self.value = epochTime()

proc newGaugeOnly*(
  name: string, documentation: string,
  labelNames: seq[string] = @[],
  namespace = "",
  unit = Unit.Unspecified,
  labelValues: seq[string] = @[]
): Gauge =
  result =
    Gauge(
      base: initMetricBase(
        name, documentation, labelNames, namespace, unit, labelValues
      ),
    )
  if labelValues.len == 0:
    result.children = initTable[seq[string], Gauge]()

proc initMetricFamilySamples*(
  name: string,
  kind: MetricType,
  documentation: string,
  unit: Unit
): MetricFamilySamples =
  MetricFamilySamples(
    name: name,
    kind: kind,
    documentation: documentation,
    unit: unit
  )

proc addMetric*(
  self: var MetricFamilySamples,
  value: float64,
  labels: openarray[(string, string)]=[]
) =
  let name =
    case self.kind
    of MetricType.Counter:
      self.name & "_total"
    of MetricType.Gauge:
      self.name
    else:
      self.name
  self.samples.add(initSample(name, @labels, value))

proc addMetric*(
  self: var MetricFamilySamples,
  value: int,
  labels: openarray[(string, string)]=[]
) =
  self.addMetric(value.float64, labels)

# TODO: Create a `Metric` concept
proc collect*[T](self: T): seq[MetricFamilySamples] =
  var metricFamily = MetricFamilySamples(
    name: self.base.name,
    documentation: self.base.documentation,
    unit: self.base.unit,
    samples: @[]
  )

  when T is Counter:
    metricFamily.kind = MetricType.Counter
  elif T is Gauge:
    metricFamily.kind = MetricType.Gauge
  else:
    {.error: "Unknown metric type".}

  for sample in self.getMultiSamples():
    metricFamily.samples.add(
      initSample(
        self.base.name & sample.suffix,
        sample.seriesLabels,
        sample.value
      )
    )
  return @[metricFamily]

proc name*(self: Counter or Gauge): string =
  return self.base.name

when isMainModule:
  # Let's test this architecture.
  var c = newCounterOnly(
    "my_requests_total",
    "HTTP Failures",
    @["method", "endpoint"]
  )

  c.labels("get", "/").inc()
  c.inc()

  for sample in getMultiSamples(c):
    echo sample