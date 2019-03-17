import tables, sets, sequtils, times, strformat, macros, algorithm, strutils

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

proc initSample*(
  name: string, seriesLabels: seq[(string, string)], value: float64
): Sample =
  return (name, seriesLabels, value)

proc initMetricSample(
  suffix: string, seriesLabels: seq[(string, string)], value: float64
): MetricSample =
  return (suffix, seriesLabels, value)

proc verifyMetricName(name: string) =
  if name[0] notin {'a'..'z', 'A'..'Z', ':'}:
    raise newException(
      ValueError, fmt"Invalid metric name, must not begin with '{name[0]}'"
    )

  for c in name:
    if c notin {'a'..'z', 'A'..'Z', '0'..'9', '_', ':'}:
      raise newException(
        ValueError, fmt"Invalid metric name, must not contain '{c}'"
      )

proc createFullName(name: string, unit: Unit): string =
  result = name
  let unitSuffix = toLower("_" & $unit)
  if unit != Unspecified and not result.endsWith(unitSuffix):
    result.add(unitSuffix)
  verifyMetricName(name)

proc initMetricBase(
  name: string,
  documentation: string,
  labelNames: seq[string],
  namespace: string,
  unit: Unit,
  labelValues: seq[string]
): MetricBase =
  MetricBase(
    name: name.createFullName(unit),
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

proc getSelfSamples*(self: Counter): seq[MetricSample] =
  # https://bit.ly/2VILoGA
  return @[
    initMetricSample("_total", @[], self.value)
  ]

proc reset*(self: var Counter) =
  self.value = float64(0)

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
  var name = name
  if name.endsWith("_total"):
    name = name[0 .. ^6]
  result =
    Counter(
      base: initMetricBase(
        name, documentation, labelNames, namespace, unit, labelValues
      ),
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

type
  Histogram* = ref object
    base: MetricBase
    children: Table[seq[string], Histogram] # Label values -> Histogram
    sum: float64
    upperBounds: seq[float64]
    buckets: seq[float64]

proc observe*(self: var Histogram, amount: float64) =
  ## Increment gauge by the given amount.
  self.sum += amount
  for i, bound in pairs(self.upperBounds):
    if amount <= bound:
      self.buckets[i] += 1
      break

proc getSelfSamples*(self: Histogram): seq[MetricSample] =
  var acc = 0.0
  for i, bound in pairs(self.upperBounds):
    acc += self.buckets[i]
    result.add(
      initMetricSample("_bucket", @{"le": $bound}, acc)
    )

  result.add(initMetricSample("_count", @[], acc))
  result.add(initMetricSample("_sum", @[], self.sum))

const
  defaultHistogramBuckets* = @[
    0.005, 0.01, 0.025, 0.05, 0.075,
    0.1, 0.25, 0.5, 0.75, 1.0, 2.5,
    5.0, 7.5, 10.0, INF
  ]

proc newHistogramOnly*(
  name: string, documentation: string,
  labelNames: seq[string] = @[],
  namespace = "",
  unit = Unit.Unspecified,
  labelValues: seq[string] = @[],
  buckets = defaultHistogramBuckets
): Histogram =
  result =
    Histogram(
      base: initMetricBase(
        name, documentation, labelNames, namespace, unit, labelValues
      ),
    )
  if "le" in labelNames:
    raise newException(
      ValueError, "Cannot use `le` label name here. Reserved by histogram."
    )
  if labelValues.len == 0:
    result.children = initTable[seq[string], Histogram]()

  # Prepare upper bounds using buckets.
  var buckets = buckets
  if not buckets.isSorted(system.cmp):
    raise newException(ValueError, "Buckets not in sorted order.")

  if buckets.len < 2:
    raise newException(ValueError, "Must have at least two buckets")

  if buckets[^1] != INF:
    buckets.add(INF)

  result.upperBounds = buckets

  # Initialize buckets.
  for b in result.upperBounds:
    result.buckets.add(0)

template time*(self: Histogram, body: untyped): untyped =
  ## Can be used to time a piece of code, observed timings will be logged to
  ## the specified histogram.
  bind epochTime
  let start = epochTime()
  body
  self.observe(epochTime() - start)

type
  MetricFamilySamples* = object
    name*: string
    kind*: MetricType
    documentation*: string
    unit*: Unit
    samples*: seq[Sample]

proc initMetricFamilySamples*(
  name: string,
  kind: MetricType,
  documentation: string,
  unit: Unit
): MetricFamilySamples =
  var name = name
  if kind == MetricType.Counter and name.endsWith("_total"):
    name = name[0 .. ^6]

  result = MetricFamilySamples(
    name: name.createFullName(unit),
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
  elif T is Histogram:
    metricFamily.kind = MetricType.Histogram
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

proc name*(self: Counter or Gauge or Histogram): string =
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