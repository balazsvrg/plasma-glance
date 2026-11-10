# Glance architecture

This document is for a developer who needs to change the widget. It describes how the code works today and
names functions and properties rather than line numbers, because line numbers drift. Search for the name.

Everything here was checked against the source in `package/`. Where a statement comes from a code comment or
from the author's notes and could not be checked by reading the code (measurements, runtime behaviour), it says so.

Contents

1. File map
2. Data flow
3. The `statOrder` model
4. The text pipeline and the width pipeline
5. The maximum-length system
6. The edge-drag handle
7. `syncLengthInfo` and the hidden config keys
8. Graphs
9. Battery
10. Fans: discovery and the icon
11. Sensor gating
12. Vertical panels
13. The settings pages
14. How to add a new stat
15. Pitfalls

---

## 1. File map

```
package/
  metadata.json                  plugin id org.local.cpumemtemp, name "Glance", version, Plasma/Applet
  contents/config/main.xml       every setting, its type and default (the kcfg schema)
  contents/config/config.qml     registers the three settings pages (ConfigCategory)
  contents/ui/main.qml           the whole widget: sensors, text, widths, strip, popup, drag handle
  contents/ui/configGeneral.qml  settings page: units, warning temperature, maximum length, refresh
  contents/ui/configMetrics.qml  settings page: the stat table (show/graph, order), fan/battery options
  contents/ui/configGraphs.qml   settings page: panel graph style, chart style, history length
  contents/ui/LengthNotice.qml   warning banner shown on the General and Metrics pages
  contents/ui/Metrics.js         registry that describes each stat as data (not yet used by the widget)
install.sh / uninstall.sh        kpackagetool6 wrappers (install or upgrade for the current user)
package.sh                       zips metadata.json + contents/ into dist/<id>-<version>.plasmoid
tests/metrics_test.py            checks the registry against main.qml (python3 + PySide6, no Plasma needed)
```

`contents/ui/Metrics.js` is a registry that describes each stat as data: its labels, settings keys and
defaults, sensors and when they are polled, panel text templates (full, compact, vertical), worst-case
samples, graph scale, alert rule and popup rows, plus the pure formatting helpers that render those templates.
The widget does not use it yet: `main.qml` and the settings pages still carry their own copies of all of this.
`tests/metrics_test.py` checks that the registry reproduces today's strings, formats and key names exactly.
It is intended to replace the per-stat switches and lists that section 14 enumerates.

`metadata.json` keeps the plugin id `org.local.cpumemtemp` although the visible name is "Glance"; Plasma stores
the applet's settings under the id, so renaming it would reset them.

`main.qml` is a single `PlasmoidItem` (`root`). Besides the root it defines these inline components, all
used from `root`'s own scope:

| Component | Role |
|---|---|
| `FanDiscovery` | one-time lookup of `lmsensors/<chip>/fanN` sensors (section 10) |
| `History` | a `Loader` that owns one `HistoryProxySource` (section 8) |
| `Spark` | the small line or bar chart used by every graph |
| `FanIcon` | the three-blade fan, stepped animation |
| `PopupRow`, `PopupGraph` | popup building blocks (`PopupGraph` extends `Spark`) |
| `Divider`, `MetricCell` | declared inside `compactRepresentation`; the panel strip |

The runtime has three views: `compactRepresentation` (the panel strip, a `MouseArea` that toggles
`root.expanded` on click), `fullRepresentation` (the popup) and the tooltip (`toolTipMainText` /
`toolTipSubText: tooltipText()`). `preferredRepresentation` is `compactRepresentation`.

---

## 2. Data flow

Two sources feed the widget: `org.kde.ksysguard.sensors` (ksystemstats) for CPU, memory, temperature,
frequency, network and fan, and Plasma's `powermanagement` data engine for the battery.

```
 ksystemstats                                   powermanagement engine
 Sensors.Sensor { sensorId, enabled,            P5Support.DataSource { engine, connectedSources,
                  updateRateLimit: refreshMs }                         interval: 5000 }
        | .value                                        | data["Battery"], data["Battery0".."]
        |                                               v
        |   fan: FanDiscovery -> fanIds           batterySummary -> batPercent, batState, batLow
        |        -> Repeater of Sensors -> fanItems     |
        |        -> fanRpmMax() -> fanRpm, fanLevel     |
        v                                               v
   statValue(id, sample) ----------------------------- (bat, fan read their own values)
        |
        +--> valueText(id, compact, sample) / netLines(sample)
        |         |
        |         v
        |    statText(id, compact, vertical) --> MetricCell Label (panel)
        |                                    \-> tooltipText() (tooltip)
        |
        +--> History { sensor, wanted } --Loader--> HistoryProxySource
                  |  cpuHist, ramHist, ... (null while inactive)
                  v
             statHistory(id) / statHistory2(id) / statYFrom(id) / statYTo(id) / statLineColor(id)
                  |
                  +--> Spark in MetricCell (behind text or inline)
                  +--> PopupGraph { statId } in a popup block

 Popup rows (PopupRow) do NOT use statText: they call the format helpers directly
 (pct, gib, freq, ghzNumber, rate, bytesText, temp, wh, batText, rpmText ...) on the sensor values.
```

The formatting helpers (`pct`, `temp`, `gib`, `rate`, `freq`, ...) test values with `isNum(v)`, which rejects `undefined`, `null`, `""` and `NaN`, so a
missing sensor shows `--` rather than a fake 0.

Sensors are declared individually in `main.qml` (`cpuUsage`, `memPercent`, `memUsed`, `memTotal`,
`tempAvg`, `tempMax`, `freqAvg`, `freqMin`, `freqMax`, `netDown`, `netUp`, `netDownTotal`, `netUpTotal`,
`coreCount`), plus dynamically created ones for fans (`fanRepeater` delegates) and per-core temperatures
(`perCore` delegates inside `tempBlock`). Every one uses `updateRateLimit: root.refreshMs` except
`coreCount`, which is read once and has no rate limit set. `refreshMs` is the setting clamped to at least 250.

---

## 3. The `statOrder` model

`statOrder` drives everything: the panel strip, the popup, the tooltip, which stats are dropped first and
the row order in the settings table.

- `defaultOrder` is `["cpu","ram","temp","freq","net","bat","fan"]`. It is the list of all stat ids.
- `statOrder` is `normalizeOrder(Plasmoid.configuration.statOrder)`. `normalizeOrder` splits the
  comma-separated string, keeps only ids found in `defaultOrder`, removes repeats, then appends any id that
  is missing. So a stat added in a later version appears at the end for existing users without migration.
- Per-stat predicates and helpers are `switch (id)` functions keyed by the stat id: `statShown`,
  `statGraph` (panel graph flag), `statPopupGraph` (popup graph flag), `popupShown`, `statHistory`,
  `statHistory2`, `statYFrom`, `statYTo`, `statAlert`, `statTextColor`, `statLineColor`, `reservedWidth`,
  `verticalCaption`, `statValue`, `valueText`, `statText`, `popupBlock`.
- `shownIds()` is `statOrder` filtered by `statShown`. For `bat` and `fan`, "shown" also needs the hardware
  (`batShown = showBat && hasBattery`, `fanShown = showFan && hasFan`).

### Panel

`compactRepresentation` contains a `GridLayout` (`layout`) holding a `Repeater` over `root.statOrder`. Each
delegate is a "slot", itself a small `GridLayout`:

```
layout (GridLayout: one row of statOrder.length + 1 columns; one column when vertical)
  Repeater over statOrder
    slot (GridLayout, visible: root.cellShown(id))
      Divider    visible: root.anyCellBefore(id)      1 px, opacity 0.3
      Loader     active: root.cellShown(id)  -> MetricCell { statId: id }
  Label "–"      visible: !root.anyCell()             placeholder (an en dash) when nothing is visible

MetricCell { statId }
  Spark                      behind the text, opacity 0.5, fills the cell  (cell.behind)
  GridLayout content
    FanIcon                  only when statId === "fan"
    Label                    text: root.statText(statId, root.statCompact(statId), vertical)
    Spark                    inline graph after the text                   (cell.inline)
```

`cellShown(id)` tests membership of `visibleIds`, which is `shownIds()` minus the stats dropped by the
maximum length. So hidden and dropped stats take no space and, because the `Loader` is inactive, build no
chart or icon. A `MetricCell` derives all its data from `statId` through the `stat*` helpers; it holds no
per-stat code except the `fan` flag (icon, and one more grid column).

The first visible slot has no divider (`anyCellBefore` is true only if the id's index in `visibleIds`
is above 0).

### Popup

`fullRepresentation` is a `ColumnLayout` with a `Repeater` over `statOrder`. Each delegate is a `Loader`
with `active: root.popupShown(modelData)` and `sourceComponent: root.popupBlock(modelData)`.
`popupBlock(id)` returns one of the `Component` blocks `cpuBlock`, `ramBlock`, `freqBlock`, `netBlock`,
`batBlock`, `fanBlock`, `tempBlock`. A block is a `ColumnLayout` of `PopupRow`s and a
`PopupGraph { statId: "..." }`. `PopupRow` uses a fixed-width name column (`popupLabelWidth`, the width of
the text "CPU temp (max core)"), so values line up between blocks. `fanBlock` builds its row by hand
because it holds a `FanIcon`. If no block is shown, a "Nothing to show" label appears (`anyPopupShown()`).

`popupShown("temp")` is true when any of `popupTempAvg`, `popupTempMax`, `popupCores` is on. For `bat` and
`fan` it uses `popupBatShown` / `popupFanShown`, which include the hardware check.

### Tooltip

`tooltipText()` walks `statOrder`, keeps `statShown` ids, and joins `statText(id, false, false)` with
`" · "`. It always uses the full horizontal text, even on a vertical panel, and it includes stats that the
maximum length dropped from the strip. Do not hard-code stat names or order anywhere else.

---

## 4. The text pipeline and the width pipeline

There is exactly one function that produces panel text and a small set that measures it. The maximum-length
calculation (`stripLength`, `computeFit`) and the on-screen layout both call them, so the calculation can
only drift from reality if somebody writes a panel string somewhere else.

### Text: `statText(id, compact, vert)`

```
statText(id, compact, vert)
  vert  -> verticalLines(id, compact, false).join("\n")
  horiz -> caption + valueText(id, compact, false)     (net and fan are special cases)

valueText(id, compact, sample)   the value part, no caption
  v = statValue(id, sample)      live value, or a worst-case value when sample is true
  cpu, ram -> pct(v)             temp -> temp(v) | tempShort(v)      freq -> freq(v) | freqShort(v)
  bat      -> batValue(v, sample ? 1 : batState, compact)            fan  -> rpmNumber(v)

netLines(sample)                 ["down", "up"] as short strings ("↓4.5M", "↑3K"); also the worst-case sample
verticalLines(id, compact, sample)   [verticalCaption(id)] + value line(s); net gives caption + netLines
```

Horizontal texts: `CPU 8%` / `C 8%`, `RAM`/`R`, `BAT 62% ↑` / `B 62%↑`, fan `2400 RPM` / `2400`, temp and
freq are value only. The net full text comes from `netText()` (`rate()` strings such as `↓4.5 MB/s`); its
compact text joins `netLines(false)`.

`sample` makes `statValue` return the widest value a stat can reach (100, 9900 MHz, 9999 RPM; net uses
`999e6` bytes/s, divided by 8 in bits mode so it is the widest in either unit). That is what width
measurements use.

`statCompact(id)` decides whether a stat's value text is shortened:

- horizontal: `lengthLevel >= 2` (the compact-text step of the maximum length);
- vertical: only for `temp`, `freq` and `bat` (the only ones with a shorter value form), and only when that
  stat's own full text (`verticalWidth(id)`) is wider than `panelThickness - 2 * smallSpacing`. Shortening
  saves no length on a vertical panel, so it is never a length step there.

### Widths

| Function | Used for |
|---|---|
| `reservedWidth(id, compact)` | horizontal: the widest text of a stat, from `TextMetrics` items |
| `verticalWidth(id)` | vertical: widest line of `verticalLines(id, false, true)` measured with `FontMetrics fm`; at least the icon size for `fan` |
| `cellLength(id, level)` | space one stat takes along the panel at a step (width, or height when vertical) |
| `stripLength(level, drop)` | length of the whole strip at a step with the last `drop` stats removed |

Horizontal: the `Label` in a `MetricCell` has `Layout.minimumWidth` and `preferredWidth` equal to
`reservedWidth(statId, statCompact(statId))`, so the strip does not resize when a number gains a digit.
`reservedWidth` returns the width of a `TextMetrics` item (`mCpu`, `mCpuC`, `mRam`, ..., `mFan`, `mFanC`)
whose `text` is a hand-written worst-case string such as `"CPU 100%"` or `"↓999 MB/s ↑999 MB/s"`. Note that
only the vertical width is derived from `statText`'s own code (via `sample`). For the horizontal width, the
reserve strings are separate text that must be kept in step with the format by hand.
`mTemp`/`mTempC` depend on `useF` (`"212°F"` vs `"100°C"`).

`cellLength` horizontal: `reservedWidth`, plus the fan icon (`iconSizes.smallMedium + smallSpacing`) for
`fan`, plus `smallSpacing + inlineGraphWidth` (`gridUnit * 4`) for an inline graph.
`cellLength` vertical: line count (`verticalLines(id, false, true).length`) times `mLine.height`, plus the
icon size for `fan`, plus `gridUnit` for an inline graph.

`stripLength(level, drop)` adds the cell lengths of the first `n = shown - drop` stats, then
`(n - 1) * (1 + 2 * gap)` (a 1 px divider and a gap on each side), rounds up, and adds a flat 1 px for layout
rounding. The gap is `spacingFor(level)` (largeSpacing, or smallSpacing at level 3) horizontally and
`rowSpacingFor(level)` (smallSpacing, or 0 at level 3) vertically. The extra 1 px was measured, per the code
comment ("seen as 1 px in every test, however many stats"), so the strip stays at or under the limit.

`inlineGraphsAt(level)` is `graphInline && level === 0`. This single rule feeds `cellLength`, `MetricCell`
(`behind` vs `inline`) and `syncLengthInfo`.

The model was verified with an overlay printing `layout.implicitWidth` next to
`stripLength(...)`; that is a manual test, not part of the repo.

---

## 5. The maximum-length system

`Plasmoid.configuration.maxLength` limits the strip along the panel (width, or height when vertical);
0 means no limit. When the strip would be longer, it saves space in steps and stops at the first step that
fits:

| Level | What changes | `spacingFor` / `rowSpacingFor` |
|---|---|---|
| 0 | full text, graphs as chosen | large / small |
| 1 | inline graphs become behind-text graphs (`inlineGraphsAt` is false), which take no length | large / small |
| 2 | compact text (`statCompact` true horizontally) | large / small |
| 3 | tight spacing | small / 0 |

If level 3 still does not fit, stats are dropped from the end of `shownIds()` one at a time
(`drop = 1, 2, ...`) at level 3; the first stat is never dropped.

- `levelList()` is `[0, 1, 2, 3]` horizontally and `[0, 1, 3]` vertically (step 2 saves no length there).
- `computeFit()` returns `{ level, drop }`. With `maxLength <= 0` or nothing shown it is `{0, 0}`.
  Otherwise it takes the first level in `levelList()` whose `stripLength(level, 0) <= maxLength`; failing
  that, the smallest `drop` for which `stripLength(3, drop) <= maxLength`; failing that, everything but the
  first stat (`drop = shown - 1`).
- `fit` is `dragging ? dragFit() : computeFit()`. `lengthLevel` is `fit.level`.
- `visibleIds` / `droppedIds` are `shownIds()` split at `shown - fit.drop`.
- `maxLength` (the root property) is `dragging ? dragMax() : Plasmoid.configuration.maxLength`, so while the
  handle is dragged, the readout and the calculation use the live value.
- `configs()` lists every layout the strip can take, longest to shortest: one entry per level in
  `levelList()` with no drops, then one per drop at level 3. Each entry is `{ level, drop, len }` with
  `len = stripLength(level, drop)`. The result is cached in `readonly property var layouts: configs()`.
  It depends only on settings (no live sensor values, because `cellLength` uses worst-case samples), so it
  is recomputed when settings change and not when a sensor ticks.

Hysteresis: for the saved limit there is none; `computeFit` is a pure function of the limit. The only
hysteresis is the halfway rule that applies while the handle is dragged (next section).

Settings pages do not recompute any of this. They read what the widget wrote (section 7).

---

## 6. The edge-drag handle

The context menu entry "Adjust length with the mouse" (`Plasmoid.contextualActions`, a checkable
`PlasmaCore.Action`; a `Binding` keeps `checked` in step with `root.adjusting`) shows a handle on the
strip's free edge. A 12 s `Timer` (`running: root.adjusting && !root.dragging`) switches adjust mode off
again.

State lives in `root`, not in the handle, so tests can drive it with temporary timers:
`adjusting`, `dragging`, `dragMoved`, `dragLength`, `dragCfg`, `handleAtStart`.

Which edge: `handleAtStart` is set by `compact.updateHandleSide()` from where the widget's centre sits in its
window: the far half of the panel (`x > width/2`, or `y > height/2` when vertical) means the widget is packed
toward the end, so the strip grows toward the start and the handle sits on the start edge. It is re-run on
`x/y/width/height` changes and on `onAdjustingChanged`, and it never flips during a drag.

The drag, in the order the handlers call it (`MouseArea grab` in the handle):

| Handler | Calls | What it does |
|---|---|---|
| `onPressed` | `beginDrag(startLength)` | `startLength` is the live `layout.implicitWidth` (or `implicitHeight`); `dragCfg` is set to the index in `layouts` that equals `computeFit()`; `dragMoved = false`; `dragging = true` |
| `onPositionChanged` (while pressed) | `dragTo(startLength, startPos, pos)` | `dragMoved = true`; `dragLength = startLength + (handleAtStart ? -1 : 1) * (pos - startPos)`; then `dragStep()` |
| `onReleased` | `finishDrag()` | `v = dragMax()`; `dragging = false`; writes `maxLength = v` only if `dragMoved` |
| `onCanceled` | `cancelDrag()` | `dragging = false`, saves nothing |
| `onDoubleClicked` | `resetLength()` | `dragging = false`, `maxLength = 0` |

The pointer is read with `mapToGlobal` (`pointerPos`), not from the handle's own coordinates, because the
handle moves as the strip changes length and a local coordinate would make the drag unsteady.

`dragStep()` implements the halfway rule over the cached `layouts` (never `configs()`):

1. `limit = snapLimit()` = `dragLength` rounded to 5 px, at least 20.
2. `fitIdx` is the first (longest) layout with `len <= limit`. If `fitIdx < dragCfg`, set `dragCfg = fitIdx`:
   growing is immediate.
3. Then, while there is a next strictly shorter layout `j` (equal or longer entries are skipped): stop if
   `limit > (cur.len + layouts[j].len) / 2`; otherwise `dragCfg = j`. So each shrink step needs the pointer at
   least halfway from the current layout's length to the next shorter one, and a small nudge never makes
   the strip jump.

`dragFit()` returns `layouts[dragCfg]`'s level and drop, which is what `fit` follows while dragging.
`dragMax()` is `max(snapLimit(), dragLayout().len)`, so the saved value is never shorter than the layout on
screen (what you see is what is saved), and a value at or above `stripLength(0, 0)` is saved as 0
("no limit"). `dragMoved` exists so that a plain click (press and release with no movement) does not rewrite
the saved length.

`finishDrag`'s direct assignment to `Plasmoid.configuration.maxLength` does not use `setCfg`; `setCfg` is
for the widget's own bookkeeping keys.

Limits of testing: no tool in the dev environment injects real mouse events, so the
`MouseArea` handlers are tested by hand; the step logic can be tested by walking `beginDrag`/`dragTo` over a list
of pointer values. The handle side cannot be tested in `plasmawindowed` without forcing `handleAtStart`.

---

## 7. `syncLengthInfo` and the hidden config keys

The settings dialog cannot see the widget's runtime state, so the widget writes it into configuration keys
that the pages read live. The keys (all in `main.xml`, described there as "written by the widget"):

| Key | Written by | Meaning |
|---|---|---|
| `lengthLevel` | `syncLengthInfo` | `fit.level` |
| `lengthTextShort` | `syncLengthInfo` | `!vertical && fit.level >= 2` |
| `lengthDropped` | `syncLengthInfo` | comma-separated ids dropped from the strip |
| `lengthInlineOff` | `syncLengthInfo` | inline graphs are currently shown behind the text because of the limit |
| `batteryCount` | `syncBatteryCount` | number of batteries, 0 if none (from the `"Battery"` source data: `"Has Battery"` true ? `"Sources".length` : 0) |
| `fanCount` | the `FanDiscovery` loader | number of fans, written when discovery is final |

`syncLengthInfo()` returns early while dragging (nothing is written during a drag). It works out
`keep = shown - fit.drop`, whether any kept stat has a panel graph (`statGraph`), and writes the four keys
through `setCfg(key, value)`, which assigns only if the value changed. It is scheduled with
`Qt.callLater` from `onFitChanged`, `onDraggingChanged`, `onVerticalChanged` and `Component.onCompleted`.
A code comment explains why it uses `fit` directly and why it is deferred: a derived property such as
`droppedIds` had stale values inside a change handler once.

Pages read the keys through `Plasmoid.configuration` (`LengthNotice.qml`; `batteryCount` and `fanCount`
in `configMetrics.qml`; `lengthDropped` and `maxLength` in `hiddenByLength`). They must not declare
`cfg_` properties for these keys, or the dialog would write stale values back. The keys persist in the
config file; this is a known trade-off.

`lengthTextShort` is false on vertical panels, and `LengthNotice` shows its text-shortened line only when it
is true; its "tight" line is `lengthLevel >= 3`. The notice is active only when `maxLength > 0` and at least
one of the four conditions holds. It reflects the saved limit and the widget's current layout, so it updates
on Apply, not while typing in the field.

---

## 8. Graphs

### History

`History` is a `Loader` component with properties `sensor`, `wanted` and `ready`:

- `ready` is latched true the first time `sensor.value` is numeric (`onNumericChanged`, or at
  `Component.onCompleted`), so a history never starts with fake zeros and a missing sensor never blocks
  another stat's graph.
- `active: wanted && ready`. When active it creates an `Item` that exposes a `Charts.HistoryProxySource`
  (`source: SingleValueSource { value: hist.sensor.value }`, `maximumHistory: root.historyLen`,
  `interval: root.refreshMs`, `fillMode: DoNotFill`). When inactive, `historySource` is `null` and
  nothing is collected.
- `historyLen` is `round(historySeconds * 1000 / refreshMs)`, at least 2; `historySeconds` is the setting
  clamped to 30..300.

There is one `History` per data series: `cpuHistory`, `ramHistory`, `tempHistory`, `freqHistory`,
`netDownHistory`, `netUpHistory` (its `wanted` follows `netDownHistory.wanted`), `fanHistory`, `batHistory`.
So net has two sources, down and up. `wanted` is "the stat is shown and its panel graph is on, or the stat is
in the popup and its popup graph is on" (for example `(gpCpu && showCpu) || (gdCpu && popupCpu)`; for
battery and fan it uses the hardware-checked `batShown`/`popupBatShown`/`fanShown`/`popupFanShown`).
`root.cpuHist`, `ramHist`, ... are the loaders' `historySource`, and `statHistory(id)` / `statHistory2(id)`
map a stat id to them. Battery and fan feed `History` through small `QtObject`s (`batSensor`, `fanSensor`)
that expose a `value`, so they look like sensors.

### Drawing

`Spark` is an `Item` that creates either a line or a bar chart (the `chartStyle` setting, read once as
`root.barChart`; the style not in use is not created, each lives in its own `Loader`).

Line: a `Charts.LineChart`: `valueSources` is one or two histories, `xRange` is automatic (spans the
samples collected so far, then scrolls), `yRange` is `yFrom..yTo` (not automatic), `direction: ZeroAtEnd`
(newest on the right), `interpolate: false`, a line of 1.5 and `fillOpacity: 0.15`. A second series uses
`lineColor2` (`positiveTextColor`).

Bar: a `Charts.BarChart` (an `XYChart`, so the same fixed `yRange`, `ZeroAtEnd` and `stacked` apply). It
has no bucketing of its own and `HistoryProxySource` does not expose its samples to QML, so:

- Each `History` also owns a small sample store (`samples`: the last `2 * historyLen` values, a running
  `count` and a `revision`). It is filled from the proxy's `dataChanged` (one per history tick) for as long
  as the `History` loader is active, in both chart styles, so a style change never loses history. It is
  never cleared; it is destroyed with the loader (graph turned off). `root.sampleStoreOf(source)` maps a
  history source to its store, so `Spark` keeps the same `history`/`history2` interface. The two net
  stores can start at different ticks, so `bucketMean` shifts the upload store by the difference of the
  two counts to line the series up by time.
- `Spark` merges samples into buckets: `barCount = floor(width / 3)` (2 px bar + 1 px gap at least),
  `bucketSize = ceil(historyLen / barCount)`, `slotCount = ceil(historyLen / bucketSize)` and
  `slotPx = floor(width / slotCount)`. Buckets are counted from the first sample, so only the newest
  one changes between ticks. `rebuild()` (scheduled with `Qt.callLater`) writes the mean of each bucket
  into a `ListModel` (row 0 = newest, which `ZeroAtEnd` draws at the right edge) read by two
  `Charts.ModelSource`s (roles `a` for the first series, `b` for the second). It reruns when the store
  changes, the chart style changes to bar, the width changes or the history length changes.
- The chart is `slotCount * slotPx` wide, anchored to the right, with `xRange` fixed to `0..slotCount`
  so a bar keeps its width while the history is still filling, `spacing: 1` and
  `barWidth: slotPx - 1`. Bar edges can be anti-aliased by about half a pixel.
- Two series are drawn stacked (download below, upload above), so the network scale covers the sum
  (see Scales).

Every graph in the widget is a `Spark`: the behind-text one in
`MetricCell` (opacity 0.5), the inline one in `MetricCell`, and `PopupGraph` (which adds `statId`, a `wanted`
extra condition used by the temperature graph so it needs its row, and its own `on`/`visible`).

Light themes: `Spark` has `lightTheme` (`Kirigami.Theme.backgroundColor.hslLightness > 0.5`, read from the
theme the graph is drawn on, so it is a live binding) and `lightFactor` (1.3). The chart's `colorSource` is
`shade(lineColor)` and `shade(lineColor2)`, where `shade` returns `Qt.darker(c, lightFactor)` on a light theme
and `c` unchanged otherwise. The fill uses the line colour, so it follows. Dark themes are unaffected.

### Scales (`statYFrom`, `statYTo`)

- temperature: `tempYMin` 20 to `tempYMax = max(100, warnTempC + 10)`
- cpu, ram, battery: 0..100
- frequency: 0..`freqPeak`, which starts at 1000 and `freqMax.onValueChanged` raises it to the highest
  maximum-frequency value seen
- fan: 0..`fanPeak`, starts at 3000, raised by `onFanRpmChanged`
- network: 0..`netPeak`. `trackNetPeak()` runs from `netDown.onValueChanged` (once per refresh; upload updates
  in the same tick) and returns at once unless a net graph is on (`gpNet || gdNet`). It sets
  `netPeak = max(100000, down, up, netPeak * 0.99^(refreshMs/1000))`: it rises immediately to the highest rate
  and decays about 1% per second of real time, whatever the refresh rate, never below 100 KB/s. With bar
  graphs on, the value fed into the max is `down + up` instead of `max(down, up)` (a stacked bar is as tall
  as the sum); the line-mode scale is unchanged.

The line colour is `statLineColor(id)`: red (`negativeTextColor`) while the stat is in alert (`statAlert`:
`temp` with `avgHot`, `bat` with `batLow`), otherwise the highlight colour.

---

## 9. Battery

The battery does not use ksystemstats `power/*` sensors. It uses a `P5Support.DataSource` on the
`powermanagement` engine, the same source KDE's own battery widget uses. The code comment and the README
say the ksystemstats sensors lagged and disagreed with the kernel on a test laptop ("stale and inconsistent", in the author's words); that is an observation of the author, not something checkable from the code.
Battery numbers are verified against `/sys/class/power_supply/BAT*` and `upower -d`.

- `connectedSources` is always `["Battery"]` (the summary, needed to know whether there is a battery at all),
  plus the individual `batterySources` (`Battery0`, ...) only while `popupBatShown`. `interval` is 5000 ms,
  independent of `refreshMs`.
- `batterySummary` keys used: `"Has Battery"` (`hasBattery`), `"Sources"` (`batterySources`), `"Percent"`
  (`batPercent`), `"State"` (`batState`: 1 charging, -1 discharging, 0 otherwise), `"Remaining msec"`
  (`batTimeText()` formats it with `hoursText`). Per battery: `"Energy"`, `"Pretty Name"`, `"Percent"`,
  `"Capacity"`, `"State"`. `batEnergyTotal()` sums `"Energy"` over the sources.
- `batLow` is `batPercent < 15 && batState <= 0`; with `avgHot` it is one of the two `statAlert` conditions.
- `batShown = showBat && hasBattery` and `popupBatShown = popupBat && hasBattery`, so everything
  downstream (strip, popup, tooltip, history) disappears on a machine without a battery.
- `syncBatteryCount(data)` writes `batteryCount`. It runs from a `Connections { target: powerSource }`
  `onNewData` handler for the `"Battery"` source and computes the count from the event's `data` argument, so
  the first answer from the engine corrects a stale saved value even if `hasBattery` never changes.
- The popup block shows the combined line, optionally one line per battery
  (`batSeparate && batterySources.length > 1`), and a charge/discharge time line. The engine reports no
  watts, so no power draw is shown.

---

## 10. Fans: discovery and the icon

### `FanDiscovery`

The fan sensor id contains the hardware chip name (`lmsensors/<chip>/fanN`), so fans are found by scanning
the sensor tree instead of hard-coding ids. The component holds a `Sensors.SensorTreeModel`, flattened by a
`KItemModels.KDescendantsProxyModel`, and a single-shot `Timer` (`fanScan`).

- The first scan runs 800 ms after load and after each row insert/remove/model reset (`fanScan.restart()`
  in the `Connections`), because the tree fills in gradually. Once a scan is not final the interval is
  set to 3000 ms and stays there, so later restarts from tree changes also wait 3 s.
- `scanNow()` collects every sensor id matching `/^lmsensors\/[^\/]+\/fan\d+$/`, sorts the list, increments
  `attempts` and builds a key (the ids joined with commas).
- The result is final only when two consecutive scans give the same non-empty key (`stable`), or when
  `attempts >= maxAttempts` (10). An empty scan resets `lastKey` to `""`, so it can never count as one of
  the two.
- If not final: a non-empty list is still emitted as `found(ids, false)` ("show what is known now, keep
  looking"), and the timer is set to 3000 ms and restarted. 10 attempts is about 30 s.

The `Loader` that hosts it (`active: !root.fanDiscoveryDone`) handles `onFound`: it assigns `fanIds` only if
the list is non-empty and different, sets `fanDiscoveryDone = final` (which unloads the component and its
models), and on `final` writes `fanCount` with `setCfg`. An empty first scan therefore never decides "no
fan" and never writes `fanCount`. After the 10 attempts with nothing found, the final result is empty and
`fanCount` is written as 0.

### Reading the fans

`fanRepeater` has `model: root.fanWanted ? root.fanIds : []` (`fanWanted = fanShown || popupFanShown`), and
each delegate holds one `Sensors.Sensor`. So fan sensors exist only while a fan is wanted. `fanItems` is
rebuilt by `collectFans(removed)` from `onItemAdded` / `onItemRemoved`; the removed delegate can still be
reachable inside the removal handler, so it is excluded explicitly. `fanRpmMax()` returns the largest RPM
among them (the fastest fan sets the speed) or `undefined`; `fanRpm` binds to it. `fanLevel` is 0 when
there is no positive reading, 1 below 2500 RPM, 2 below 4000, else 3.

### `FanIcon`

Three blades from rounded rectangles, `level` 0..3, `color`, `animate`. Effects appear only while
`animate && level > 0`: level 2 adds one faint trail layer, level 3 adds two trails, a soft disc, a small
shake (the `frame` counter flips the offset) and three swirling speed lines.

The spin is a stepped `Timer`, not an animator: `interval: 80` (12.5 steps per second), running only while
`animate && level > 0 && visible && width > 0`. Each tick adds 10, 22 or 40 degrees to `rotor.rotation` by
level; a step stays under 60 degrees so a three-blade fan never appears to turn backwards. The icon is used
in the panel (`MetricCell`) and in the popup (`fanBlock`); in both, `visible` stops the timer when the item is
not on screen.

Measured cost (the author's measurement, not reproducible from the code): a smooth 60 fps `RotationAnimator` cost about
26% of one core (widget plus `kwin_wayland`) in a `plasmawindowed` test, the 12 fps stepped timer about
8.5%. Keep animations stepped, run them only while visible and needed, and re-measure with `/proc/<pid>/stat`
(widget and `kwin_wayland`) when adding any.

---

## 11. Sensor gating

A sensor that nothing shows is switched off with `enabled:`. Three tiers, all visible in the declarations in
`main.qml`:

- Needed by the panel or the popup: `show* || popup*` (for example `cpuUsage`: `showCpu || popupCpu`;
  `freqMax` and the network down/up sensors follow the same pattern, and `tempAvg` uses `showTemp ||
  popupTempAvg`).
- Needed only by the popup: `popup* && root.expanded` (`memUsed`, `memTotal`, `tempMax`, `freqMin`,
  `netDownTotal`, `netUpTotal`, `coreCount`). So they are read only while the popup is open.
- Created on demand: fan sensors (delegates of `fanRepeater`, only while `fanWanted`) and per-core sensors
  (delegates of `perCore` inside `tempBlock`, which exists only as long as the popup's Loader for the temp
  block is active). A code comment says these exist only while the popup is open; that depends on how Plasma
  instantiates `fullRepresentation`, which was not checked here.

Graph history is a separate gate (`History.wanted`, section 8): it needs the graph flag and the stat to be
shown. Battery data is always connected for the `"Battery"` summary (section 9) and the individual batteries
only while the popup shows them.

---

## 12. Vertical panels

`vertical` is `Plasmoid.formFactor === PlasmaCore.Types.Vertical`. What changes:

- The strip is a single column (`columns: 1`); the `Divider` fills the width; the layout's minimum width is 0
  and `Layout.fillWidth` is true, so the panel's thickness sets the width.
- A stat's text is its lines joined by newlines: the caption (`verticalCaption`: "CPU", "RAM", "Temp",
  "Freq", "Net", "Bat", "Fan") and then the value line, or for net the two `netLines`. The caption is always
  kept; only the value is shortened, and only when it is wider than the panel (`statCompact`). The `Label`
  uses `fontSizeMode: Text.HorizontalFit` with `minimumPixelSize: 8`.
- `compact` (the `MouseArea`) publishes `panelThickness` (its width when vertical, else 0) to `root` through a
  `Binding`; `statCompact` reads it.
- Lengths are heights: `cellLength` multiplies the line count by `mLine.height` ("Ag" in the default font)
  and adds the icon height for `fan` and `gridUnit` for an inline graph. Level 2 is skipped (`levelList()`),
  and `lengthTextShort` is never true.
- The handle runs along the vertical axis (`SizeVerCursor`, `y`, `height`).
- `MetricCell`'s inner `GridLayout` has its `width`/`height` bound explicitly (`parent.width`/`parent.height`
  when vertical, `implicitWidth`/`implicitHeight` otherwise). The code comment explains that switching between
  `anchors.fill` and `anchors.centerIn` once left the old filled size behind after an orientation change
  and scrambled the horizontal strip.

The vertical branches of `cellLength` are estimates: they do not model per-line spacing or the font shrinking.
`plasmawindowed` cannot simulate a vertical panel, so test it in a real panel.

---

## 13. The settings pages

### Registration and the `cfg_` convention

`contents/config/config.qml` is a `ConfigModel` with three `ConfigCategory` items (`General`, `Metrics`,
`Graphs`) whose `source` names a page file. Every setting lives in `main.xml` (groups `General`, `Popup`,
`Graphs`; the group names carry no meaning to the code). A page is a `KCM.SimpleKCM` that declares, for each
user setting it edits:

- `property <type> cfg_<key>` (bound by Plasma to the setting), and
- `property <type> cfg_<key>Default` (set by Plasma to the schema default, used by the Defaults button).

`configGeneral.qml` uses `property alias cfg_warnTemp: warnTemp.value` (and `refreshMs`, `maxLength`) for the
spin boxes and plain properties for the two combo boxes. Combo boxes use a `Binding` element for
`currentIndex` and set `cfg_*` in `onActivated`; the comment says a `Binding` survives user input, unlike a
plain binding, so Defaults and external changes keep updating the box.

Split by page: General has `useFahrenheit`, `netBits`, `warnTemp`, `refreshMs`, `maxLength`. Graphs has
`panelGraphStyle` (stored as 1 behind text, 2 inline; an old 0 shows as "Behind text"), `chartStyle` (stored as
1 line, 2 bar; anything else shows as "Line"; `main.qml` carries `chartStyleBar` = 2 as a copy of the stored
value) and `historySeconds`
(the combo snaps to the nearest of 30/60/300). Metrics has everything else a user sets (`statOrder`, the
`show*`, `graphPanel*`, `popup*`, `graphPopup*`, `batSeparate`, `fanAnimate`). The hidden keys of section 7
have no `cfg_` property anywhere. `main.qml` carries `styleInline` = 2 as a copy of the stored value and its
comment says to keep it in step with `configGraphs.qml`.

### The Metrics page

- `stats` is a list of `{ id, name, show, graph, popup, popupGraph }`, where the last four are setting names.
  `statInfo(id)` looks it up; `cfgGet(key)` / `cfgSet(key, value)` read and write `page["cfg_" + key]`, so rows
  are generic.
- `orderModel` (a `ListModel` of `statId`) is the table's order. `loadOrder(text)` fills it from a
  `statOrder` string, dropping unknown ids and appending missing ones; `currentOrder()` serialises it.
  `onCfg_statOrderChanged` reloads the model only if the setting differs from `currentOrder()`, so the
  page follows outside changes (dialog opening, Defaults) but not its own writes.
- `moveRow(from, to)` is the one function both the drag handle and the arrow buttons call: it moves the
  model row and then writes `cfg_statOrder = currentOrder()`. `Kirigami.ListItemDragHandle` calls it from
  `onMoveRequested`.
- `rowAvailable(id)` is false for `bat` when `batteryCount` is 0 and for `fan` when `fanCount` is 0 (both read
  live from `Plasmoid.configuration`). Unavailable rows have `visible: false` and zero height.
  `visiblePosition(index)` counts only available rows so the row stripes alternate correctly.
  `stepTarget(from, dir)` returns the nearest available row in a direction (or -1 at the ends); the arrow
  buttons use it for their target and for `enabled`. `allGraphs(popup)` / `setAllGraphs(popup, on)` (the "All
  graphs" row) also skip unavailable rows and leave their settings alone.
- The `temp` row has two `SubRow`s (hottest core, per-core temperatures) that belong to the temp stat and
  move with it. The page also shows the fan animation checkbox when `hasFan` and the popup battery view combo
  box when `batteryCount > 1`.
- `StatName` marks a row "hidden by the maximum length" using `hiddenByLength(id)`, which reads
  `lengthDropped` and `maxLength`. `LengthNotice` is placed at the top of the General and Metrics pages (not
  Graphs).
- Table styling (colours checked by hand, not in code): a `Rectangle` with
  `Kirigami.Theme.colorSet: View`; the stripe uses `alternateBackgroundColor` unless it equals
  `backgroundColor`, then blends 4% of the text colour into the background.

### `LengthNotice`

A `Kirigami.InlineMessage` with no `cfg_` properties. It reads `lengthInlineOff`, `lengthTextShort`,
`lengthLevel`, `lengthDropped` and `maxLength` from `Plasmoid.configuration` and builds its bullet list from
them. It has its own `statName(id)` switch (a second copy of the stat names).

---

## 14. How to add a new stat

Replace `X` with the stat. Items 1 to 4 are the data, 5 to 9 the panel, 10 the popup, 11 and 12 the
settings. Everything else (strip layout, tooltip, `syncLengthInfo`, `configs()`, dragging, the
`GridLayout` column count) is generic over `statOrder` and needs no change.

1. `contents/config/main.xml`: add `showX`, `popupX`, `graphPanelX`, `graphPopupX` (with defaults), and any
   other setting the stat needs. Add the id to the `statOrder` default string (not required for upgrades,
   because `normalizeOrder` and `loadOrder` append missing ids, but the Defaults button uses this string).
   If it depends on hardware, add a `xCount` Int entry that the widget writes.
2. `main.qml`, settings properties: `readonly property bool showX`, `popupX`, and the graph flags `gpX` and
   `gdX` (next to `gpCpu`, `gdCpu`, ...).
3. `main.qml`, sensors: add `Sensors.Sensor { id: ...; sensorId: "..."; updateRateLimit: root.refreshMs;
   enabled: ... }`. Use `root.showX || root.popupX` for what the panel and popup need, and
   `root.popupX && root.expanded` for popup-only details. If the sensor is hardware-dependent, add a
   `hasX` / `xShown` / `popupXShown` set like `hasBattery` / `batShown` / `popupBatShown`, and write
   `xCount` with `setCfg` from the code that finds it (compare `syncBatteryCount` and the `FanDiscovery`
   loader, and be careful not to decide "none" from an empty first look).
4. `main.qml`, history (if the stat can have a graph): add `History { id: xHistory; sensor: ...; wanted:
   (root.gpX && root.showX) || (root.gdX && root.popupX) }`, a `readonly property var xHist:
   xHistory.historySource`, and a scale peak property if the scale is not 0..100. If the stat is not a
   sensor (like battery and fan), wrap its value in a `QtObject { readonly property var value: ... }`.
5. `main.qml`, ordering and flags: add the id to `defaultOrder`, and a case to `statShown` (use the
   hardware-checked property), `statGraph` (`gpX`) and `statPopupGraph` (`gdX`).
6. `main.qml`, widths: add `TextMetrics m<X>` and `m<X>C` with the widest full and compact text (the
   horizontal reserve is not derived from `statText`), and the cases in `reservedWidth`. If the stat has an
   icon or other fixed extra content, add it to `cellLength` for both orientations (as for `fan`).
7. `main.qml`, text: add `statValue(id, sample)` (live value, and a worst-case sample), the case in
   `valueText` (the value part, with `compact` and `sample`), the horizontal case in `statText` (caption plus
   value, or `v` alone), and the `verticalCaption`. `verticalLines` is generic; a stat with more than one
   value line needs a special case like `net`. If its vertical value has a shorter form, add its id to the
   list in `statCompact` (`temp`, `freq`, `bat`) and handle `compact` in `valueText`.
8. `main.qml`, helpers: `statAlert` (if it can alert), `statHistory` (and `statHistory2` for a second
   line), `statYTo` (and `statYFrom`) if the scale is not 0..100.
9. `main.qml`, `MetricCell`: nothing for a text-only stat. For an icon, follow `cell.fan` (the extra grid
   column and the icon item).
10. `main.qml`, popup: a case in `popupShown`, a case in `popupBlock`, and a `Component { id: xBlock; ...}`
    holding `PopupRow`s and `PopupGraph { statId: "x" }`. Gate any popup-only sensor with `&& root.expanded`.
11. `configMetrics.qml`: add the entry to `stats` (id, translated name, the four setting names); add
    `cfg_*` and `cfg_*Default` properties for every new key; if hardware-dependent, add the `xCount`
    read (`Plasmoid.configuration.xCount`), a `hasX` property and a case in `rowAvailable`. Do not declare
    `cfg_xCount`.
12. `LengthNotice.qml`: add a case to its own `statName(id)`.
13. Version and docs: bump the version in `metadata.json` before `./package.sh`; update the README.

Check the result by running `plasmawindowed org.local.cpumemtemp` and looking at a screenshot. QML load
errors appear in the window, not on stderr. There is no `qmllint` here.

---

## 15. Pitfalls

Each of these is visible in the code or its comments, except where marked.

- A one-line `if (a) x = y else break` is a QML/JavaScript syntax error and stops the whole widget from
  loading (it did once during development). The code uses braces or separate lines. Look at the window after
  every edit; errors do not reach stderr.
- Do not read a derived property inside a change handler: `droppedIds` was stale when `fit`'s handler ran.
  `syncLengthInfo` computes from `fit` and is scheduled with `Qt.callLater`.
- Do not call `configs()` on every mouse move. Use the `layouts` cache; `beginDrag` and `dragStep` read
  it. `configs()` is only called from the binding that fills `layouts`.
- Do not hand-write a panel string or width outside `statText` / `reservedWidth` / `verticalWidth` /
  `cellLength`; the max-length calculation and the layout would disagree. When you change a text format, also
  update the `m*` reserve strings, which are separate.
- Do not give a settings page a `cfg_` property for a key the widget writes (`length*`, `batteryCount`,
  `fanCount`), or Apply writes stale values back.
- `FontMetrics.advanceWidth` is not bindable. `verticalWidth` starts with `void fm.font` so the width is
  measured again when the font changes.
- Do not switch `MetricCell`'s inner layout between `anchors.fill` and `anchors.centerIn`; bind
  `width`/`height` explicitly (section 12).
- In `fanRepeater.onItemRemoved`, the removed delegate may still be reachable; `collectFans(removed)` leaves it
  out.
- Fan discovery must never treat an empty scan as final, and `fanCount` is written only on the final result.
- Keep animations stepped and visible-only (section 10); a smooth animator was measured as about three
  times as costly (the author's figures).
- Gate every sensor that only an optional stat or the popup uses (section 11), or it polls for data nobody
  sees.
- Use named enums (`PlasmaCore.Types.Vertical`, `Kirigami.MessageType.Warning`) rather than numbers. The
  exception in the code is the stored graph style (1 or 2), duplicated as `styleInline` in `main.qml` and as
  `currentIndex + 1` in `configGraphs.qml`.
- Write widget-owned settings with `setCfg` (writes only on change). Plain assignment is used only for the
  user-visible `maxLength` in `finishDrag` and `resetLength`.
- `syncBatteryCount` must keep reading the `newData` event's `data`, not the derived `hasBattery` /
  `batterySources` properties, which can be stale inside a change handler.
- Vertical panels cannot be tested with `plasmawindowed`, and the vertical branches of `cellLength` are
  estimates. Real mouse events cannot be injected in the dev environment, so the handle's `MouseArea`
  handlers are only tested by hand.
- The stat names exist in two places in the settings code (`stats` in `configMetrics.qml` and `statName` in
  `LengthNotice.qml`) and the id switch statements are repeated in `main.qml`; a new stat must touch all of
  them (section 14).
