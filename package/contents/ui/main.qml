import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.quickcharts as Charts
import org.kde.plasma.plasma5support as P5Support
import org.kde.kitemmodels as KItemModels
import "Metrics.js" as M

PlasmoidItem {
    id: root

    // ---- user settings (contents/config/main.xml) ----
    readonly property int refreshMs: Math.max(250, Plasmoid.configuration.refreshMs)
    readonly property real warnTempC: Plasmoid.configuration.warnTemp
    readonly property bool showCpu: Plasmoid.configuration.showCpu
    readonly property bool showRam: Plasmoid.configuration.showRam
    readonly property bool showTemp: Plasmoid.configuration.showTemp
    readonly property bool showFreq: Plasmoid.configuration.showFreq
    readonly property bool showNet: Plasmoid.configuration.showNet
    readonly property bool netBits: Plasmoid.configuration.netBits
    readonly property bool showBat: Plasmoid.configuration.showBat
    readonly property bool useF: Plasmoid.configuration.useFahrenheit
    readonly property bool popupCpu: Plasmoid.configuration.popupCpu
    readonly property bool popupMemory: Plasmoid.configuration.popupMemory
    readonly property bool popupTempAvg: Plasmoid.configuration.popupTempAvg
    readonly property bool popupTempMax: Plasmoid.configuration.popupTempMax
    readonly property bool popupCores: Plasmoid.configuration.popupCores
    readonly property bool popupFreq: Plasmoid.configuration.popupFreq
    readonly property bool popupNet: Plasmoid.configuration.popupNet
    readonly property bool popupBat: Plasmoid.configuration.popupBat
    readonly property bool batSeparate: Plasmoid.configuration.batSeparate
    readonly property bool showFan: Plasmoid.configuration.showFan
    readonly property bool popupFan: Plasmoid.configuration.popupFan
    readonly property bool fanAnimate: Plasmoid.configuration.fanAnimate
    // Write a setting only when it changed (avoids needless config writes and change signals).
    function setCfg(key, value) {
        var c = Plasmoid.configuration
        if (c[key] !== value) c[key] = value
    }

    // ---- graph scale peaks ----
    // A graph scale that follows the data (registry: scale.mode, i.e. frequency, network and fan) needs a peak that
    // outlives the individual values. The peak is state, so it lives here: `peaks` maps a stat id to its current
    // peak (missing: the scale's floor, the start value). Metrics.js computes every step (M.stepPeak, a pure
    // function); the three triggers below call stepPeak() exactly where the old per-stat code ran: the frequency
    // maximum, the network download value and the fan speed changing. `peaks` is replaced, never changed in place,
    // so a binding that reads a peak is notified; a plain map (not objects created at start-up) also means a step
    // taken while the item tree is still being created is not lost.
    property var peaks: ({})
    function peakOf(id) {
        var p = peaks[id]
        return p === undefined ? M.byId(id).scale.floor : p
    }
    // One step of a stat's peak. The time that passed since the last step is the refresh interval (the triggers
    // run once per sensor update), so the decay of the network scale is about 1% per second whatever the rate.
    function stepPeak(id) {
        var prev = peakOf(id)
        var ctx = { barChart: barChart, graphOn: statGraph(id) || statPopupGraph(id) }
        var next = M.stepPeak(M.byId(id), prev, statVals(id), ctx, refreshMs)
        if (next === prev) return
        var map = {}
        for (var k in peaks) map[k] = peaks[k]
        map[id] = next
        peaks = map
    }

    // ---- sensors (IDs verified with `kstatsviewer --list`) ----
    // One Sensor per `sensors` entry of the registry (Metrics.js: sensor id, and the gate that says when it is
    // polled), so nothing polls for data nobody sees. `sensorItems` maps "<stat id>.<name>" to the created item and
    // is a property, so a lookup made before the items existed is made again once they do (as reserveItems).
    readonly property var sensorKinds: M.sensorKinds()
    property var sensorItems: ({})
    // A value that arrives while its sensor is still being created reaches onValueChanged before the item is in
    // sensorItems (the step would read nothing), so once every sensor exists each trigger sensor that already has a
    // number steps its peak once.
    function stepTriggerPeaks() {
        for (var i = 0; i < M.METRICS.length; ++i) {
            var t = M.METRICS[i].scale.trigger
            if (t && isNum(sensorValue(M.METRICS[i].id, t))) stepPeak(M.METRICS[i].id)
        }
    }
    readonly property var coreCount: sensorValue("temp", "coreCount")
    function sensorOf(id, name) { return sensorItems[id + "." + name] || null }
    function sensorValue(id, name) {
        var s = sensorOf(id, name)
        return s ? s.value : undefined
    }
    // The inputs of M.sensorActive for a stat, read live from the settings (Plasmoid.configuration[key] is reactive).
    function sensorFlags(id) {
        var k = M.byId(id).keys, c = Plasmoid.configuration, opts = {}
        for (var o in k.options) opts[o] = !!c[k.options[o]]
        return { show: !!c[k.show], popup: !!c[k.popup], expanded: root.expanded, opts: opts }
    }
    Instantiator {
        id: sensorInst
        model: root.sensorKinds
        delegate: Sensors.Sensor {
            required property var modelData
            readonly property var entry: M.byId(modelData.id).sensors[modelData.name]
            readonly property string key: modelData.id + "." + modelData.name
            sensorId: entry.id
            readonly property bool isTrigger: M.byId(modelData.id).scale.trigger === modelData.name
            updateRateLimit: entry.noRateLimit ? 0 : root.refreshMs
            enabled: M.sensorActive(entry, root.sensorFlags(modelData.id))
            // The sensor a following scale names as its trigger steps the peak once per refresh (the hardware
            // maximum is not a sensor, so a graph's scale grows to the highest value seen).
            onValueChanged: if (isTrigger) root.stepPeak(modelData.id)
        }
        onObjectAdded: {
            // The map is built once, when the last sensor exists (every binding that reads it re-evaluates once).
            if (count !== root.sensorKinds.length) return
            root.sensorItems = sensorMap()
            root.stepTriggerPeaks()
        }
        function sensorMap() {
            var map = {}
            for (var i = 0; i < count; ++i) {
                var it = objectAt(i)
                if (it) map[it.key] = it
            }
            return map
        }
    }
    // ---- battery ----
    // Data comes from Plasma's power-management engine, the same source KDE's own
    // battery widget uses. (KDE's ksystemstats power sensors lag and disagree with
    // the kernel on some laptops, so they are not used.) The "Battery" source is the
    // combined summary; Battery0, Battery1, ... are the individual batteries.
    P5Support.DataSource {
        id: powerSource
        engine: "powermanagement"
        connectedSources: root.popupBatShown ? ["Battery"].concat(root.batterySources) : ["Battery"]
        interval: 5000
    }
    readonly property var batterySummary: powerSource.data["Battery"] ? powerSource.data["Battery"] : ({})
    readonly property var batterySources: batterySummary["Sources"] ? batterySummary["Sources"] : []
    readonly property bool hasBattery: batterySummary["Has Battery"] === true
    readonly property bool batShown: showBat && hasBattery
    readonly property bool popupBatShown: popupBat && hasBattery
    function batteryData(key) { var d = powerSource.data[key]; return d ? d : ({}) }

    // The settings pages read the battery count from the config (they cannot see the engine).
    // Written from the "Battery" source's own newData event and computed from the event's data
    // (derived properties can be stale inside a change handler). The first event is the engine's
    // real answer, so a saved count is corrected even if hasBattery never changes.
    function syncBatteryCount(data) {
        setCfg("batteryCount", data["Has Battery"] === true && data["Sources"] ? data["Sources"].length : 0)
    }
    Connections {
        target: powerSource
        function onNewData(sourceName, data) { if (sourceName === "Battery") root.syncBatteryCount(data) }
    }

    readonly property var batPercent: isNum(batterySummary["Percent"]) ? Number(batterySummary["Percent"]) : undefined
    readonly property int batState: batterySummary["State"] === "Charging" ? 1
                                    : (batterySummary["State"] === "Discharging" ? -1 : 0)
    function batEnergyTotal() {          // Wh held across all batteries
        var total = 0, any = false
        for (var i = 0; i < batterySources.length; ++i) {
            var e = batteryData(batterySources[i])["Energy"]
            if (isNum(e)) { total += Number(e); any = true }
        }
        return any ? total : undefined
    }
    // Lets the graph history treat the combined percentage like a sensor.
    QtObject { id: batSensor; readonly property var value: root.batPercent }

    // ---- fan ----
    // The fan sensor ID contains the hardware chip name (lmsensors/<chip>/fanN), so
    // fans are discovered from the sensor tree instead of being hard-coded.
    property var fanIds: []
    property bool fanDiscoveryDone: false
    readonly property bool hasFan: fanIds.length > 0
    readonly property bool fanShown: showFan && hasFan
    readonly property bool popupFanShown: popupFan && hasFan
    readonly property bool fanWanted: fanShown || popupFanShown

    component FanDiscovery: Item {
        id: fanDisc
        signal found(var ids, bool final)         // final: stop looking (found some, or gave up)
        property int attempts: 0
        property string lastKey: ""             // the previous non-empty scan
        readonly property int maxAttempts: 10     // about 30 s: the sensor tree can fill in slowly at login

        Sensors.SensorTreeModel { id: fanTree }
        KItemModels.KDescendantsProxyModel { id: fanFlat; model: fanTree }
        // The tree fills in gradually, so scan a moment after the last change.
        Timer { id: fanScan; interval: 800; onTriggered: fanDisc.scanNow() }
        Connections {
            target: fanFlat
            function onRowsInserted() { fanScan.restart() }
            function onRowsRemoved()  { fanScan.restart() }
            function onModelReset()   { fanScan.restart() }
        }
        Component.onCompleted: fanScan.restart()

        function scanNow() {
            var ids = [], n = fanFlat.rowCount()
            for (var i = 0; i < n; ++i) {
                var id = String(fanFlat.data(fanFlat.index(i, 0), Sensors.SensorTreeModel.SensorId))
                if (/^lmsensors\/[^\/]+\/fan\d+$/.test(id)) ids.push(id)
            }
            ids.sort()
            ++attempts
            // Final only when two consecutive scans agree on a non-empty list (a second chip may
            // appear after the first), or when the attempts run out.
            var key = ids.join(",")
            var stable = ids.length > 0 && key === lastKey
            lastKey = ids.length > 0 ? key : ""
            if (stable || attempts >= maxAttempts) {
                found(ids, true)
            } else {
                if (ids.length > 0) found(ids, false) // show what is known now, keep looking
                fanScan.interval = 3000               // an empty tree may just be slow: look again
                fanScan.restart()
            }
        }
    }

    // Runs until it has found the fans (or has looked for about 30 s and given up), then unloads:
    // it is a one-time lookup and the sensor-tree models are not needed afterwards. An empty first scan
    // never decides "no fan", and never overwrites the saved fanCount.
    Loader {
        active: !root.fanDiscoveryDone
        sourceComponent: FanDiscovery {
            onFound: function (ids, final) {
                if (ids.length > 0 && JSON.stringify(ids) !== JSON.stringify(root.fanIds))
                    root.fanIds = ids
                root.fanDiscoveryDone = final
                if (final) setCfg("fanCount", ids.length)
            }
        }
    }

    property var fanItems: []
    Repeater {
        id: fanRepeater
        model: root.fanWanted ? root.fanIds : []
        onItemAdded: root.fanItems = collectFans(null)
        onItemRemoved: function (index, item) { root.fanItems = collectFans(item) }
        // The delegate being removed may still be reachable here, so leave it out explicitly.
        function collectFans(removed) {
            var items = []
            for (var i = 0; i < count; ++i) { var it = itemAt(i); if (it && it !== removed) items.push(it) }
            return items
        }
        delegate: Item {
            id: fanSensorItem
            required property var modelData
            Sensors.Sensor { id: fanS; sensorId: fanSensorItem.modelData; updateRateLimit: root.refreshMs }
            readonly property var rpm: fanS.value
        }
    }

    // The fastest fan sets the speed.
    function fanRpmMax() {
        var best = 0, any = false
        for (var i = 0; i < fanItems.length; ++i) {
            var v = fanItems[i].rpm
            if (isNum(v)) { best = Math.max(best, Number(v)); any = true }
        }
        return any ? best : undefined
    }
    readonly property var fanRpm: fanRpmMax()
    // 0 stopped, 1 slow, 2 medium, 3 fast: drives the icon's spin speed.
    readonly property int fanLevel: !isNum(fanRpm) || fanRpm <= 0 ? 0 : (fanRpm < 2500 ? 1 : (fanRpm < 4000 ? 2 : 3))
    onFanRpmChanged: root.stepPeak("fan")
    QtObject { id: fanSensor; readonly property var value: root.fanRpm }

    // ---- graph history ----
    // Each stat has its own history. It is collected only while a graph that
    // shows that stat is enabled, and it starts once the stat's sensor has
    // reported a real number (so the history never begins with fake zeros).
    readonly property int styleInline: 2   // stored value of "Inline"; keep in sync with configGraphs.qml (1 = behind text)
    readonly property int panelGraphStyle: Plasmoid.configuration.panelGraphStyle
    readonly property bool graphInline: panelGraphStyle === styleInline   // anything else (incl. an old 0) is "behind"
    readonly property int chartStyleBar: 2   // stored value of "Bar"; keep in sync with configGraphs.qml (1 = line)
    readonly property bool barChart: Plasmoid.configuration.chartStyle === chartStyleBar   // anything else is "line"
    readonly property int historySeconds: Math.min(300, Math.max(30, Plasmoid.configuration.historySeconds))
    readonly property int historyLen: Math.max(2, Math.round(historySeconds * 1000 / refreshMs))

    component History: Loader {
        id: hist
        property string statId                // registry id and series name: how the history is looked up
        property string series
        property var sensor
        property bool wanted: false
        property bool ready: false          // latched once the sensor has reported a number
        readonly property var historySource: item ? item.history : null
        readonly property var sampleStore: item ? item.store : null
        readonly property bool numeric: !!sensor && root.isNum(sensor.value)

        onNumericChanged: if (numeric) ready = true
        Component.onCompleted: if (numeric) ready = true

        active: wanted && ready
        sourceComponent: Item {
            readonly property var history: h
            Charts.HistoryProxySource {
                id: h
                source: Charts.SingleValueSource { value: hist.sensor ? hist.sensor.value : undefined }
                maximumHistory: root.historyLen
                interval: root.refreshMs
                fillMode: Charts.HistoryProxySource.DoNotFill
            }
            // The chart source keeps its samples to itself, so bar graphs get their own copy of the
            // recent values (one per history tick). It fills in both chart styles, so switching style
            // keeps the whole history, and it lives and dies with this loader.
            readonly property var store: samples
            QtObject {
                id: samples
                property var values: []          // the most recent samples, oldest first
                property int count: 0            // samples seen since the store started
                property int revision: 0         // changes whenever a sample is added
                function add(v) {
                    values.push(v)
                    if (values.length > 2 * root.historyLen) values.splice(0, values.length - 2 * root.historyLen)
                    count++
                    revision++
                }
            }
            Connections {
                target: h
                function onDataChanged() { if (hist.numeric) samples.add(Number(hist.sensor.value)) }
            }
        }
    }

    // One History per series of each registry entry (`series`: net has two, down and up), created by the Repeater
    // below. A History exists (is active) only while a graph of its stat is enabled (see historyWanted) and its
    // sensor has reported a number; the sample stores fill whenever it is active. The lookups below find a
    // History by stat id and series name. historyItems is a property that is reassigned as the delegates are
    // created, so a lookup made before they existed is made again once they do.
    property var historyItems: []
    readonly property var historyKinds: {
        var list = []
        for (var i = 0; i < M.METRICS.length; ++i)
            for (var j = 0; j < M.METRICS[i].series.length; ++j)
                list.push({ id: M.METRICS[i].id, series: M.METRICS[i].series[j] })
        return list
    }
    // Where a series' values come from: an object with a `value`. A plain-sensor stat's series is the sensor of the
    // same name (registry: series keys are sensor names); battery and fan wrap their value in a small QtObject.
    function historySensor(id, series) {
        if (id === "bat") return batSensor
        if (id === "fan") return fanSensor
        return sensorOf(id, series)
    }
    Repeater {
        id: historyRepeater
        model: root.historyKinds
        delegate: History {
            required property var modelData
            statId: modelData.id
            series: modelData.series
            sensor: root.historySensor(modelData.id, modelData.series)
            wanted: root.historyWanted(modelData.id)
        }
        onItemAdded: root.historyItems = historyList()
        function historyList() {
            var list = []
            for (var i = 0; i < count; ++i) { var it = itemAt(i); if (it) list.push(it) }
            return list
        }
    }
    // A history is collected while a graph that shows the stat is enabled: the panel graph while the stat is shown
    // in the panel, the popup graph while its popup row is on. All series of a stat share the condition.
    function historyWanted(id) {
        return (statGraph(id) && statShown(id)) || (statPopupGraph(id) && statPopupOn(id))
    }
    function historyOf(id, series) {
        for (var i = 0; i < historyItems.length; ++i)
            if (historyItems[i].statId === id && historyItems[i].series === series) return historyItems[i]
        return null
    }
    // The bar graphs' sample store belonging to one of the history sources.
    function sampleStoreOf(source) {
        if (!source) return null
        for (var i = 0; i < historyItems.length; ++i)
            if (historyItems[i].historySource === source) return historyItems[i].sampleStore
        return null
    }

    // One small graph, a line or bars (Graphs tab); used by the panel cells and the popup. Both styles
    // read the same history, scale and colours. Only the style in use is created.
    component Spark: Item {
        id: spark
        property var history: null
        property var history2: null          // optional second series (e.g. upload)
        property real yFrom: 0
        property real yTo: 100
        property color lineColor: Kirigami.Theme.highlightColor
        property color lineColor2: Kirigami.Theme.positiveTextColor
        // On a light theme the lines (and their fill, which uses the line colour) are drawn a little
        // darker so they keep their contrast. The check follows the theme live.
        property real lightFactor: 1.3
        readonly property bool lightTheme: Kirigami.Theme.backgroundColor.hslLightness > 0.5
        function shade(c) { return lightTheme ? Qt.darker(c, lightFactor) : c }

        // Bars: neighbouring samples are merged so that every bar is at least 2 px wide with a 1 px gap,
        // and a bar shows the mean of its samples. Buckets are counted from the first sample, so a bar only
        // changes while it is the newest and the others stay put until a new bar starts.
        readonly property int barSlot: 3                                     // px per bar, gap included
        readonly property int barCount: Math.max(1, Math.floor(width / barSlot))
        readonly property int bucketSize: Math.max(1, Math.ceil(root.historyLen / barCount))
        // The bars the whole history needs, each a whole number of pixels wide.
        readonly property int slotCount: Math.max(1, Math.min(barCount, Math.ceil(root.historyLen / bucketSize)))
        readonly property int slotPx: Math.max(barSlot, Math.floor(width / slotCount))
        readonly property var store: root.sampleStoreOf(history)
        readonly property var store2: root.sampleStoreOf(history2)

        // The mean of the samples of bucket `id` (0 when the bucket has none). `shift` is how many samples
        // later than the main store this one started, so both series line up by time.
        function bucketMean(s, id, shift) {
            if (!s) return 0
            var first = s.count - s.values.length
            var lo = Math.max(id * bucketSize - shift, first)
            var hi = Math.min(id * bucketSize + bucketSize - 1 - shift, s.count - 1)
            if (hi < lo) return 0
            var sum = 0
            for (var a = lo; a <= hi; ++a) sum += s.values[a - first]
            return sum / (hi - lo + 1)
        }
        // Row 0 is the newest bucket (the chart draws row 0 at the right edge, see ZeroAtEnd below).
        function rebuild() {
            if (!root.barChart || !store) return
            var newest = Math.floor((store.count - 1) / bucketSize)
            var rows = 0
            for (var j = 0; j < slotCount && newest - j >= 0; ++j) {
                if (store.count - store.values.length > (newest - j + 1) * bucketSize - 1) break   // no samples left for this bar
                var row = { a: bucketMean(store, newest - j, 0), b: store2 ? bucketMean(store2, newest - j, store.count - store2.count) : 0 }
                if (rows < barModel.count) barModel.set(rows, row)
                else barModel.append(row)
                ++rows
            }
            if (rows === 0) { rows = 1; barModel.set(0, { a: 0, b: 0 }) }      // keep one row so the model has its roles
            if (barModel.count > rows) barModel.remove(rows, barModel.count - rows)
        }
        function scheduleRebuild() { if (root.barChart) Qt.callLater(rebuild) }   // line mode keeps no bar model
        onSlotCountChanged: scheduleRebuild()
        onBucketSizeChanged: scheduleRebuild()
        onStoreChanged: scheduleRebuild()
        Component.onCompleted: scheduleRebuild()
        Connections { target: root; function onBarChartChanged() { spark.scheduleRebuild() } }
        Connections { target: spark.store; function onRevisionChanged() { spark.scheduleRebuild() } }
        Connections { target: spark.store2; function onRevisionChanged() { spark.scheduleRebuild() } }
        ListModel { id: barModel; ListElement { a: 0; b: 0 } }
        Charts.ModelSource { id: barDown; model: barModel; roleName: "a" }
        Charts.ModelSource { id: barUp; model: barModel; roleName: "b" }

        Loader {
            anchors.fill: parent
            active: !root.barChart
            sourceComponent: Charts.LineChart {
                valueSources: spark.history ? (spark.history2 ? [spark.history, spark.history2] : [spark.history]) : []
                colorSource: Charts.ArraySource { array: [spark.shade(spark.lineColor), spark.shade(spark.lineColor2)] }
                xRange { automatic: true }            // spans the samples collected so far
                yRange { from: spark.yFrom; to: spark.yTo; automatic: false }
                direction: Charts.XYChart.ZeroAtEnd   // newest sample on the right
                lineWidth: 1.5
                fillOpacity: 0.15
                interpolate: false
            }
        }
        Loader {
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: spark.slotCount * spark.slotPx
            active: root.barChart
            sourceComponent: Charts.BarChart {
                // The two series (download, upload) are stacked, so the scale covers their sum.
                stacked: true
                spacing: 1
                barWidth: spark.slotPx - spacing
                valueSources: spark.history ? (spark.history2 ? [barDown, barUp] : [barDown]) : []
                colorSource: Charts.ArraySource { array: [spark.shade(spark.lineColor), spark.shade(spark.lineColor2)] }
                xRange { from: 0; to: spark.slotCount; automatic: false }   // fixed bar width, newest bar at the edge
                yRange { from: spark.yFrom; to: spark.yTo; automatic: false }
                direction: Charts.XYChart.ZeroAtEnd   // newest sample on the right
            }
        }
    }

    // A small three-blade fan drawn from rounded rectangles, in the theme's text colour.
    // It looks faster as the fan does (all effects are shown only while animating):
    //   level 1 (slow)   plain blades
    //   level 2 (medium) one faint motion-blur trail behind each blade
    //   level 3 (fast)   two trails, a soft blurred disc, a small shake and swirling speed lines
    // The spin only runs while the fan is turning and the icon is visible.
    component FanIcon: Item {
        id: fanIcon
        property int level: 0                  // 0 stopped, 1 slow, 2 medium, 3 fast
        property color color: Kirigami.Theme.textColor
        property bool animate: true
        property int frame: 0                  // counts animation steps (drives the shake)
        implicitWidth: Kirigami.Units.iconSizes.smallMedium
        implicitHeight: implicitWidth

        readonly property bool fx: animate && level > 0        // effects only while animating
        readonly property int trails: !fx ? 0 : (level >= 3 ? 2 : (level === 2 ? 1 : 0))
        readonly property real shake: (fx && level >= 3) ? width * 0.05 : 0

        Item {
            id: shaker
            width: fanIcon.width
            height: fanIcon.height
            x: fanIcon.frame % 2 === 0 ? -fanIcon.shake : fanIcon.shake
            y: fanIcon.frame % 2 === 0 ? fanIcon.shake * 0.6 : -fanIcon.shake * 0.6

            Item {
                id: rotor
                anchors.fill: parent
                scale: (fanIcon.fx && fanIcon.level >= 3) ? 0.8 : 1      // leaves room for the speed lines

                // Soft blurred disc: the blades smear into a circle at top speed.
                Rectangle {
                    visible: fanIcon.fx && fanIcon.level >= 3
                    anchors.centerIn: parent
                    width: parent.width * 0.94
                    height: width
                    radius: width / 2
                    color: fanIcon.color
                    opacity: 0.12
                }

                // Layer 0 is the real blades; layers 1 and 2 are fading trails behind them.
                Repeater {
                    model: 3
                    Item {
                        id: layer
                        required property int index
                        anchors.fill: parent
                        visible: index <= fanIcon.trails
                        rotation: -index * 15
                        opacity: index === 0 ? 1 : (index === 1 ? 0.38 : 0.2)
                        z: -index

                        Repeater {
                            model: 3
                            Rectangle {
                                required property int index
                                width: fanIcon.width * 0.30
                                height: fanIcon.height * 0.44
                                radius: width / 2
                                color: fanIcon.color
                                x: (fanIcon.width - width) / 2
                                y: fanIcon.height * 0.04
                                transform: Rotation {
                                    origin.x: width / 2
                                    origin.y: fanIcon.height / 2 - y
                                    angle: index * 120 + 20     // the 20 degree offset gives the blades a pitch
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: fanIcon.width * 0.20
                    height: width
                    radius: width / 2
                    color: fanIcon.color
                }
            }

            // Cartoon speed lines: short dashes along the rim that swirl with the fan.
            Item {
                anchors.fill: parent
                visible: fanIcon.fx && fanIcon.level >= 3
                rotation: rotor.rotation * 0.5
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: fanIcon.width * 0.22
                        height: Math.max(1, fanIcon.width * 0.07)
                        radius: height / 2
                        color: fanIcon.color
                        opacity: 0.75
                        x: (fanIcon.width - width) / 2
                        y: 0
                        transform: Rotation {
                            origin.x: width / 2
                            origin.y: fanIcon.height / 2 - y
                            angle: index * 120 + 60
                        }
                    }
                }
            }
        }

        // Stepped at ~12 frames per second instead of a smooth 60 fps animation: at this icon
        // size it still reads as spinning, but it wakes the panel and compositor far less often.
        // Each step stays under 60 degrees so a three-blade fan never appears to turn backwards.
        Timer {
            interval: 80
            repeat: true
            running: fanIcon.animate && fanIcon.level > 0 && fanIcon.visible && fanIcon.width > 0
            onTriggered: {
                rotor.rotation = (rotor.rotation + (fanIcon.level === 1 ? 10 : (fanIcon.level === 2 ? 22 : 40))) % 360
                if (fanIcon.level >= 3) fanIcon.frame = (fanIcon.frame + 1) % 1000    // only the shake uses it
            }
        }
    }

    // ---- formatting helpers ----
    // Accepts any real numeric value; rejects undefined, null, "" and NaN so a
    // missing sensor shows "--" instead of a fake 0.
    function isNum(v) {
        return v !== undefined && v !== null && v !== "" && isFinite(Number(v))
    }
    // The settings the registry's formatters read (Metrics.js is a pure library: it cannot see root's
    // properties). Every text and width binding reads this property, so it re-evaluates when one changes.
    readonly property var textCtx: ({ useF: useF, netBits: netBits })
    // Thin wrappers for the popup rows: the formatters live in Metrics.js (M.FORMATS); the settings they
    // need come in through textCtx, read here so the calling binding re-evaluates when they change.
    function pct(v)  { return M.FORMATS.pct(v) }
    function temp(v) { return M.FORMATS.temp(v, textCtx) }
    function gib(v)  { return M.FORMATS.gib(v) }
    function wh(v)   { return M.FORMATS.wh(v) }
    function rate(v) { return M.FORMATS.rate(v, textCtx) }
    function bytesText(v) { return M.FORMATS.bytes(v) }
    function ghzNumber(v) { return M.FORMATS.ghz(v) }
    function freq(v) { return M.FORMATS.freq(v) }
    // The popup's battery row: the percentage, the state arrow and the energy of all batteries.
    function batRowText() {
        return M.render(M.byId("bat").popup.rows[0].value, { percent: batPercent, state: batState, energy: batEnergyTotal() }, textCtx)
    }
    // Hours as "3h 12m" or "45m"; empty when it cannot be estimated.
    function hoursText(hours) {
        if (!isFinite(hours) || hours < 0 || hours > 99) return ""
        var h = Math.floor(hours), m = Math.round((hours - h) * 60)
        if (m === 60) { h++; m = 0 }
        return (h > 0 ? h + "h " : "") + m + "m"
    }
    // PowerDevil's estimate: time to full while charging, time left while discharging.
    function batTimeText() {
        var ms = batterySummary["Remaining msec"]
        if (batState === 0 || !isNum(ms) || Number(ms) <= 0) return ""
        return hoursText(Number(ms) / 3600000)
    }
    // The settings the registry's alerts and scales read (Metrics.js is a pure library). Every binding that
    // evaluates an alert or a scale reads this property, so it re-evaluates when the warning temperature changes.
    // (A peak step also needs barChart and graph flags; stepPeak() reads them when it runs.)
    readonly property var limitCtx: ({ warnTempC: warnTempC })

    // Every shown stat, in the user's order, as the panel writes it (also the ones hidden by the maximum length).
    function tooltipText() {
        var parts = []
        for (var i = 0; i < statOrder.length; ++i)
            if (statShown(statOrder[i])) parts.push(statText(statOrder[i], false, false))
        return parts.join(" · ")
    }

    // ---- maximum length ----
    // Along the panel direction: width on a horizontal panel, height on a vertical one.
    // When the strip would be longer than the limit it saves space in steps and stops at
    // the first step that fits:
    //   0  full text, graphs as chosen
    //   1  inline graphs become behind-text graphs (those take no length)
    //   2  compact text (CPU 8% -> C 8%, 2.2 GHz -> 2.2G, ...), still readable (horizontal panels only:
    //      on a vertical panel compact text saves no length, so levelList() skips this step and a stat is
    //      shortened only when its own text is wider than the panel, see statCompact)
    //   3  tight spacing
    // If even that is too long, stats are dropped from the end of the user's order (Fan, Battery, Net,
    // Freq, Temp, RAM in the default order) until it fits. The first stat in the order is never dropped.
    // The tooltip always lists everything.

    // The saved limit (px, 0 = no limit), or the live value while the edge handle is being dragged.
    readonly property int maxLength: dragging ? dragMax() : Plasmoid.configuration.maxLength
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    // The order is the user's (Metrics tab); it drives the panel strip and the popup. It is also the
    // priority when space is short: stats are dropped from the end, and the first one is never dropped.
    readonly property var defaultOrder: ["cpu", "ram", "temp", "freq", "net", "bat", "fan"]
    readonly property var statOrder: normalizeOrder(Plasmoid.configuration.statOrder)
    // Keep only known stats, without repeats, and add any that are missing (e.g. after an upgrade).
    function normalizeOrder(text) {
        var ids = text ? String(text).split(",") : []
        var out = []
        for (var i = 0; i < ids.length; ++i)
            if (defaultOrder.indexOf(ids[i]) >= 0 && out.indexOf(ids[i]) < 0) out.push(ids[i])
        for (var j = 0; j < defaultOrder.length; ++j)
            if (out.indexOf(defaultOrder[j]) < 0) out.push(defaultOrder[j])
        return out
    }

    function statShown(id) {
        switch (id) {
        case "cpu":  return showCpu
        case "ram":  return showRam
        case "temp": return showTemp
        case "freq": return showFreq
        case "net":  return showNet
        case "bat":  return batShown
        case "fan":  return fanShown
        }
        return false
    }
    // The graph flags of a stat are the registry's config keys (gp: panel graph, gd: popup graph), read from the
    // configuration by name: a binding that calls these still re-evaluates when the setting changes.
    function statGraph(id) {
        var m = M.byId(id)
        return !!m && !!Plasmoid.configuration[m.keys.gp]
    }
    function statPopupGraph(id) {
        var m = M.byId(id)
        return !!m && !!Plasmoid.configuration[m.keys.gd]
    }
    // Whether the stat's row is on in the popup (its popup flag, and the battery / fan exists).
    function statPopupOn(id) {
        var m = M.byId(id)
        if (!m || !Plasmoid.configuration[m.keys.popup]) return false
        return id === "bat" ? hasBattery : (id === "fan" ? hasFan : true)
    }
    function shownIds() {
        var ids = []
        for (var i = 0; i < statOrder.length; ++i) if (statShown(statOrder[i])) ids.push(statOrder[i])
        return ids
    }

    // Widest possible text per stat and kind (full, compact), so the strip does not resize when a number gains
    // a digit. One TextMetrics per registry entry and kind; the text is the registry's worst-case sample
    // rendered with the same templates as the panel. (TextMetrics.width, not FontMetrics.advanceWidth: the
    // two differ by a fraction of a pixel, and the strip has always been sized from the former.)
    // "<id>" / "<id>C" -> TextMetrics. Empty until the Instantiator below has created its items (the first
    // evaluations of fit-dependent bindings see width 0 and are re-run). Do not write config synchronously from
    // such a binding; syncLengthInfo() is deferred with Qt.callLater for this reason.
    property var reserveItems: ({})
    Instantiator {
        id: reserveInst
        model: root.reserveKinds
        delegate: TextMetrics {
            required property var modelData
            readonly property string statId: modelData.id
            readonly property bool compact: modelData.compact
            font: Kirigami.Theme.defaultFont
            text: M.reserveText(M.byId(statId), compact, root.textCtx)
        }
        // The map is a property, so a width read before the items existed is read again once they do.
        onObjectAdded: root.reserveItems = reserveMap()
        function reserveMap() {
            var map = {}
            for (var i = 0; i < count; ++i) {
                var it = objectAt(i)
                if (it) map[it.statId + (it.compact ? "C" : "")] = it
            }
            return map
        }
    }
    readonly property var reserveKinds: {
        var list = []
        for (var i = 0; i < M.METRICS.length; ++i) {
            list.push({ id: M.METRICS[i].id, compact: false })
            list.push({ id: M.METRICS[i].id, compact: true })
        }
        return list
    }
    FontMetrics { id: fm; font: Kirigami.Theme.defaultFont }                        // width of any string
    TextMetrics { id: mLine;  font: Kirigami.Theme.defaultFont; text: "Ag" }       // one line of text

    function reservedWidth(id, compact) {
        var item = reserveItems[id + (compact ? "C" : "")]
        return item ? item.width : 0
    }

    // Widest line of a stat's text on a vertical panel (what must fit in the panel's thickness): the
    // worst-case lines of verticalLines, so the width and the text come from the same code.
    function verticalWidth(id) {
        void fm.font                         // re-measure when the font changes (advanceWidth is not bindable)
        var lines = verticalLines(id, false, true), w = 0
        for (var i = 0; i < lines.length; ++i) w = Math.max(w, fm.advanceWidth(lines[i]))
        if (hasIcon(id)) w = Math.max(w, Kirigami.Units.iconSizes.smallMedium)
        return Math.ceil(w)
    }
    // The panel's thickness (set by the vertical compact view); 0 until known or when horizontal.
    property real panelThickness: 0
    // Whether a stat's value text is shortened. Horizontal: the length step. Vertical: only this stat's own
    // full text being wider than the panel (shortening saves no length there, so it is not a length step).
    function statCompact(id) {
        if (!vertical) return lengthLevel >= 2
        // Only a stat with a shorter vertical form can change; measuring the rest could never change its text.
        var m = M.byId(id)
        if (!m || !m.panel.verticalCompact) return false
        return panelThickness > 0 && verticalWidth(id) > panelThickness - Kirigami.Units.smallSpacing * 2
    }

    // Per-stat colours, history and graph scale, so a panel cell needs nothing but its id.
    // Whether a stat is in its alert state (the registry's `alert`: temperature at or above the warning, battery
    // low). A stat without an alert reads none of its values, so its colour bindings do not follow its sensor.
    function statAlert(id) {
        var m = M.byId(id)
        if (!m || !m.alert) return false
        return M.alertOf(m, statVals(id), limitCtx)
    }
    function statTextColor(id) { return statAlert(id) ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor }
    function statLineColor(id) { return statAlert(id) ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor }
    // The history of a stat's first series (and of its second, e.g. upload): null while no graph needs it.
    function statHistory(id) {
        var m = M.byId(id), h = m ? historyOf(id, m.series[0]) : null
        return h ? h.historySource : null
    }
    function statHistory2(id) {
        var m = M.byId(id), h = m && m.series.length > 1 ? historyOf(id, m.series[1]) : null
        return h ? h.historySource : null
    }
    // The graph scale of a stat (registry `scale`): fixed, computed from the warning temperature, or the peak kept above.
    function statYFrom(id) {
        var m = M.byId(id)
        return m ? M.scaleFrom(m) : 0
    }
    function statYTo(id) {
        var m = M.byId(id)
        if (!m) return 100
        return M.scaleEnd(m, limitCtx, M.followsData(m) ? peakOf(id) : 0)
    }

    // ---- panel text ----
    // The values a stat's templates read, live (keys as in the registry's templates).
    function statVals(id) {
        switch (id) {
        case "bat":  return { percent: batPercent, state: batState }
        case "fan":  return { value: fanRpm }
        }
        return sensorVals(id)
    }
    // The values of a plain-sensor stat that the panel text, alert and scale read, under the registry's sensor
    // names (a sensor that is switched off reports undefined). Popup-only sensors are left out, so their updates
    // do not re-evaluate the panel bindings.
    function sensorVals(id) {
        var vals = {}
        var names = M.panelSensorNames(M.byId(id))
        for (var i = 0; i < names.length; ++i) vals[names[i]] = sensorValue(id, names[i])
        return vals
    }
    // The text of a stat in the panel, for the current step (compact or full) and orientation, from the
    // registry's templates. On a vertical panel the caption line is always kept, so it is easy to tell
    // which stat is shown; only the value line is shortened.
    function statText(id, compact, vert) {
        var m = M.byId(id)
        return m ? M.panelText(m, compact, vert, statVals(id), textCtx) : ""
    }
    // The lines of a stat on a vertical panel: caption, then the value line(s). `sample` gives the widest
    // possible values instead of the live ones.
    function verticalLines(id, compact, sample) {
        var m = M.byId(id)
        if (!m) return []
        return M.verticalLines(m, compact, sample ? M.sampleVals(m, true, textCtx) : statVals(id), textCtx)
    }
    // Stats with a fixed-size icon before the text (the fan), from the registry.
    function hasIcon(id) {
        var m = M.byId(id)
        return !!m && m.panel.decoration === "fanIcon"
    }

    // Space one stat takes at a given step (width when horizontal, height when vertical).
    // Inline graphs take length, so they are only drawn inline at the first (full) step; from step 1 on
    // they are drawn behind the text. This one rule feeds the width calculation, the strip and the
    // settings warning.
    function inlineGraphsAt(level) { return graphInline && level === 0 }
    readonly property real inlineGraphWidth: Kirigami.Units.gridUnit * 4       // used by the calculation and the strip
    function cellLength(id, level) {
        var compact = level >= 2
        var inlineGraph = inlineGraphsAt(level) && statGraph(id)
        var gap = Kirigami.Units.smallSpacing
        if (!vertical) {
            var w = reservedWidth(id, compact)
            if (hasIcon(id)) w += Kirigami.Units.iconSizes.smallMedium + gap
            if (inlineGraph) w += gap + inlineGraphWidth
            return w
        }
        var h = verticalLines(id, false, true).length * mLine.height    // caption + value line(s)
        if (hasIcon(id)) h += Kirigami.Units.iconSizes.smallMedium
        if (inlineGraph) h += Kirigami.Units.gridUnit
        return h
    }
    function spacingFor(level) {
        return level >= 3 ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing
    }
    function rowSpacingFor(level) {
        return level >= 3 ? 0 : Kirigami.Units.smallSpacing
    }
    // Length of the strip at a step, with the last `drop` stats removed.
    function stripLength(level, drop) {
        var ids = shownIds()
        var n = ids.length - drop
        if (n <= 0) return 0
        var total = 0
        for (var i = 0; i < n; ++i) total += cellLength(ids[i], level)
        var gap = vertical ? rowSpacingFor(level) : spacingFor(level)
        // A 1 px divider and two gaps between stats. Rounded up, plus a pixel for layout rounding (seen as
        // 1 px in every test, however many stats), so the strip stays at or under the limit.
        return Math.ceil(total + (n - 1) * (1 + 2 * gap)) + 1
    }
    // The steps the strip can take, longest first. Step 2 (compact text) saves no length on a vertical panel,
    // so it is skipped there.
    function levelList() { return vertical ? [0, 1, 3] : [0, 1, 2, 3] }
    function computeFit() {
        var ids = shownIds()
        if (maxLength <= 0 || ids.length === 0) return { level: 0, drop: 0 }
        var levels = levelList()
        for (var k = 0; k < levels.length; ++k)
            if (stripLength(levels[k], 0) <= maxLength) return { level: levels[k], drop: 0 }
        for (var drop = 1; drop < ids.length; ++drop)
            if (stripLength(3, drop) <= maxLength) return { level: 3, drop: drop }
        return { level: 3, drop: ids.length - 1 }                         // only the first stat is left
    }
    // While the handle is dragged the layout follows dragStep() (with a halfway rule for shrinking);
    // otherwise it follows the saved limit.
    readonly property var fit: dragging ? dragFit() : computeFit()
    readonly property int lengthLevel: fit.level
    // The shown stats split into those that fit and those dropped from the end to fit.
    readonly property var visibleIds: { var ids = shownIds(); return ids.slice(0, ids.length - fit.drop) }
    readonly property var droppedIds: { var ids = shownIds(); return ids.slice(ids.length - fit.drop) }

    // ---- adjusting the limit with the mouse ----
    // Right-click > "Adjust length with the mouse" shows a handle on the strip's far edge
    // (right edge, or bottom edge on a vertical panel). Dragging it resizes the strip live;
    // the value is saved on release. Dragging out to the full length means "no limit".
    property bool adjusting: false           // handle visible
    property bool dragging: false            // handle being dragged
    property bool dragMoved: false           // the pointer moved since the press (a plain click saves nothing)
    property real dragLength: 0              // strip length under the mouse, px
    // Which edge carries the handle: the edge that is free to move. A widget in the far half of the
    // panel (right half, or bottom half when vertical) is packed toward the end, so the strip grows
    // toward the start and the handle sits on the left (top) edge. Otherwise it sits on the right (bottom).
    property bool handleAtStart: false
    // Strip length for a pointer at `pos`, given where the drag started. With the handle on the
    // start edge, moving the pointer toward the start makes the strip longer, so the sign flips.
    function dragTo(startLength, startPos, pos) {
        dragMoved = true
        dragLength = startLength + (handleAtStart ? -1 : 1) * (pos - startPos)
        dragStep()
    }
    // Every layout the strip can take, from longest to shortest: the four steps with all stats,
    // then dropping stats one by one at the tightest step.
    function configs() {
        var list = []
        var n = shownIds().length
        var levels = levelList()
        for (var k = 0; k < levels.length; ++k) list.push({ level: levels[k], drop: 0, len: stripLength(levels[k], 0) })
        for (var drop = 1; drop < n; ++drop) list.push({ level: 3, drop: drop, len: stripLength(3, drop) })
        return list
    }
    // Computed once per change of settings (not once per mouse move while dragging).
    readonly property var layouts: configs()
    property int dragCfg: 0                  // index into layouts of the layout shown while dragging
    function snapLimit() { return Math.max(20, Math.round(dragLength / 5) * 5) }     // pointer limit, snapped to 5 px
    function dragLayout() { return layouts[Math.min(dragCfg, layouts.length - 1)] }
    function dragFit() {
        var c = dragLayout()
        return { level: c.level, drop: c.drop }
    }
    function beginDrag(startLength) {
        var cfgs = layouts
        var cur = computeFit()
        dragCfg = 0
        for (var i = 0; i < cfgs.length; ++i)
            if (cfgs[i].level === cur.level && cfgs[i].drop === cur.drop) { dragCfg = i; break }
        dragLength = startLength
        dragMoved = false
        dragging = true
    }
    // Growing is immediate: as soon as a longer layout fits, it is shown. Shrinking is deliberate:
    // each step down only happens once the pointer has gone at least halfway from where the current
    // layout fits to where the next shorter one fits, so a small nudge never makes the strip jump.
    function dragStep() {
        var cfgs = layouts
        var limit = snapLimit()
        var fitIdx = cfgs.length - 1
        for (var i = 0; i < cfgs.length; ++i) if (cfgs[i].len <= limit) { fitIdx = i; break }
        if (fitIdx < dragCfg) dragCfg = fitIdx                               // a longer layout fits: grow
        while (dragCfg < cfgs.length - 1) {
            var cur = cfgs[dragCfg].len
            var j = dragCfg + 1
            while (j < cfgs.length && cfgs[j].len >= cur) ++j                // next strictly shorter layout
            if (j >= cfgs.length) break
            if (limit > (cur + cfgs[j].len) / 2) break                         // not yet halfway
            dragCfg = j
        }
    }
    // The limit that would be saved right now: what is on screen, never shorter than the shown layout.
    function dragMax() {
        var v = Math.max(snapLimit(), dragLayout().len)
        return v >= stripLength(0, 0) ? 0 : v
    }
    function finishDrag() {
        if (!dragging) return
        var v = dragMax()
        dragging = false
        if (dragMoved) Plasmoid.configuration.maxLength = v     // a plain click leaves the saved length alone
    }
    function cancelDrag() { dragging = false }                  // a cancelled press saves nothing
    function resetLength() {
        dragging = false
        Plasmoid.configuration.maxLength = 0
    }
    function lengthReadout() { return maxLength === 0 ? "No limit" : maxLength + " px" }

    Plasmoid.contextualActions: [
        PlasmaCore.Action {
            id: adjustAction
            text: i18n("Adjust length with the mouse")
            icon.name: "zoom-fit-width"
            checkable: true
            onTriggered: root.adjusting = !root.adjusting
        }
    ]
    Binding { target: adjustAction; property: "checked"; value: root.adjusting }
    // Leave adjust mode on its own after a while without interaction.
    Timer { interval: 12000; running: root.adjusting && !root.dragging; onTriggered: root.adjusting = false }

    // Tell the settings pages what the maximum length is currently doing, so they can say so.
    // They read these live from the configuration; nothing is written while the handle is dragged.
    function syncLengthInfo() {
        if (dragging) return
        // Work from `fit` directly: properties derived from it (droppedIds) may not have updated yet
        // at the moment fit's change handler runs.
        var ids = shownIds()
        var keep = ids.length - fit.drop
        var graphVisible = false
        for (var i = 0; i < keep; ++i) if (statGraph(ids[i])) graphVisible = true
        var inlineOff = graphInline && !inlineGraphsAt(fit.level) && graphVisible
        var dropped = ids.slice(keep).join(",")
        setCfg("lengthLevel", fit.level)
        setCfg("lengthTextShort", !vertical && fit.level >= 2)
        setCfg("lengthDropped", dropped)
        setCfg("lengthInlineOff", inlineOff)
    }
    // Run after the current round of binding updates has settled.
    onFitChanged: Qt.callLater(syncLengthInfo)
    onDraggingChanged: Qt.callLater(syncLengthInfo)
    onVerticalChanged: Qt.callLater(syncLengthInfo)
    Component.onCompleted: Qt.callLater(syncLengthInfo)

    function cellShown(id) { return visibleIds.indexOf(id) >= 0 }
    function anyCellBefore(id) { return visibleIds.indexOf(id) > 0 }
    function anyCell() { return visibleIds.length > 0 }

    preferredRepresentation: compactRepresentation
    toolTipMainText: "System stats"
    toolTipSubText: tooltipText()

    compactRepresentation: MouseArea {
        id: compact
        onClicked: root.expanded = !root.expanded

        readonly property bool vertical: root.vertical
        Binding { target: root; property: "panelThickness"; value: compact.vertical ? compact.width : 0 }

        // Decide which edge gets the drag handle from where this widget sits in the panel.
        function updateHandleSide() {
            if (root.dragging) return                       // never flip in the middle of a drag
            var win = compact.Window.window
            if (!win) return
            var c = compact.mapToItem(null, compact.width / 2, compact.height / 2)
            root.handleAtStart = vertical ? c.y > win.height / 2 : c.x > win.width / 2
        }
        onXChanged: updateHandleSide()
        onYChanged: updateHandleSide()
        onWidthChanged: updateHandleSide()
        onHeightChanged: updateHandleSide()
        Component.onCompleted: updateHandleSide()
        Connections {
            target: root
            function onAdjustingChanged() { compact.updateHandleSide() }
        }

        Layout.minimumWidth: vertical ? 0 : layout.implicitWidth
        Layout.minimumHeight: layout.implicitHeight
        Layout.preferredWidth: vertical ? -1 : layout.implicitWidth
        Layout.preferredHeight: layout.implicitHeight
        Layout.fillWidth: vertical

        // Thin divider spanning the full panel thickness (full height on a
        // horizontal panel, full width on a vertical one).
        component Divider: Rectangle {
            color: Kirigami.Theme.textColor
            opacity: 0.3
            Layout.fillWidth: compact.vertical
            Layout.fillHeight: !compact.vertical
            Layout.preferredWidth: compact.vertical ? -1 : 1
            Layout.preferredHeight: compact.vertical ? 1 : -1
        }

        // One metric in the panel: its text (from root.statText, so the width calculation and
        // the layout always agree) plus an optional graph, drawn behind the text or after it.
        component MetricCell: Item {
            id: cell
            property string statId
            readonly property bool fan: statId === "fan"       // show the spinning fan icon before the text
            readonly property color textColor: root.statTextColor(statId)
            readonly property var history: root.statHistory(statId)
            readonly property var history2: root.statHistory2(statId)
            readonly property real yFrom: root.statYFrom(statId)
            readonly property real yTo: root.statYTo(statId)
            readonly property color lineColor: root.statLineColor(statId)

            readonly property bool graphOn: root.statGraph(statId)   // this stat's panel graph toggle
            readonly property bool hasGraph: graphOn && history !== null
            // Inline graphs take length, so they turn into behind-text graphs when space is short.
            readonly property bool behind: hasGraph && !root.inlineGraphsAt(root.lengthLevel)
            readonly property bool inline: hasGraph && root.inlineGraphsAt(root.lengthLevel)

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight

            Spark {
                visible: cell.behind
                anchors.fill: parent
                opacity: 0.5
                history: cell.behind ? cell.history : null
                history2: cell.behind ? cell.history2 : null
                yFrom: cell.yFrom
                yTo: cell.yTo
                lineColor: cell.lineColor
            }

            GridLayout {
                id: content
                // Centred at its natural size on a horizontal strip; filling the cell when vertical. Sizes are
                // bound explicitly: switching between anchors.fill and centerIn leaves the last filled size
                // behind after an orientation change while running, which scrambled the horizontal strip.
                anchors.centerIn: parent
                width: compact.vertical ? parent.width : implicitWidth
                height: compact.vertical ? parent.height : implicitHeight
                columns: compact.vertical ? 1 : (cell.fan ? 3 : 2)
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: 0

                FanIcon {
                    visible: cell.fan
                    Layout.alignment: Qt.AlignCenter
                    level: root.fanLevel
                    animate: root.fanAnimate
                    color: cell.textColor
                }
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignCenter
                    Layout.minimumWidth: compact.vertical ? 0 : root.reservedWidth(cell.statId, root.statCompact(cell.statId))
                    Layout.preferredWidth: compact.vertical ? -1 : root.reservedWidth(cell.statId, root.statCompact(cell.statId))
                    Layout.fillWidth: compact.vertical
                    horizontalAlignment: Text.AlignHCenter
                    fontSizeMode: compact.vertical ? Text.HorizontalFit : Text.FixedSize
                    minimumPixelSize: 8
                    text: root.statText(cell.statId, root.statCompact(cell.statId), compact.vertical)
                    color: cell.textColor
                }
                Spark {
                    visible: cell.inline
                    Layout.alignment: Qt.AlignCenter
                    Layout.fillWidth: compact.vertical
                    Layout.preferredWidth: compact.vertical ? -1 : root.inlineGraphWidth
                    Layout.preferredHeight: Kirigami.Units.gridUnit * (compact.vertical ? 1 : 1.2)
                    history: cell.inline ? cell.history : null
                    history2: cell.inline ? cell.history2 : null
                    yFrom: cell.yFrom
                    yTo: cell.yTo
                    lineColor: cell.lineColor
                }
            }
        }

        GridLayout {
            id: layout
            anchors.fill: parent
            columns: compact.vertical ? 1 : root.statOrder.length + 1
            columnSpacing: root.spacingFor(root.lengthLevel)
            rowSpacing: root.rowSpacingFor(root.lengthLevel)

            // One slot per stat, in the user's order: a divider (only after the first shown stat)
            // followed by the stat's cell. Hidden stats take no space.
            Repeater {
                model: root.statOrder
                delegate: GridLayout {
                    id: slot
                    required property string modelData
                    visible: root.cellShown(modelData)
                    columns: compact.vertical ? 1 : 2
                    columnSpacing: layout.columnSpacing
                    rowSpacing: layout.rowSpacing
                    Layout.alignment: Qt.AlignCenter
                    Layout.fillWidth: compact.vertical
                    Layout.fillHeight: !compact.vertical

                    Divider { visible: root.anyCellBefore(slot.modelData) }
                    // Built only while the stat is shown, so hidden stats cost no charts or icons.
                    Loader {
                        active: root.cellShown(slot.modelData)
                        Layout.alignment: Qt.AlignCenter
                        Layout.fillWidth: true          // text stays centred between the dividers
                        Layout.fillHeight: !compact.vertical
                        sourceComponent: MetricCell { statId: slot.modelData }
                    }
                }
            }
            PlasmaComponents.Label {
                visible: !root.anyCell()
                Layout.alignment: Qt.AlignCenter
                text: "–"
            }
        }

        // ---- drag handle (shown by "Adjust length with the mouse") ----
        Rectangle {
            id: handle
            visible: root.adjusting
            z: 50
            x: compact.vertical ? 0 : (root.handleAtStart ? 0 : compact.width - width)
            y: compact.vertical ? (root.handleAtStart ? 0 : compact.height - height) : 0
            width: compact.vertical ? compact.width : Kirigami.Units.smallSpacing * 2
            height: compact.vertical ? Kirigami.Units.smallSpacing * 2 : compact.height
            color: Kirigami.Theme.highlightColor
            opacity: grab.pressed ? 0.95 : (grab.containsMouse ? 0.8 : 0.5)

            Rectangle {            // grip line
                anchors.centerIn: parent
                width: compact.vertical ? Kirigami.Units.gridUnit : 2
                height: compact.vertical ? 2 : Kirigami.Units.gridUnit
                radius: 1
                color: Kirigami.Theme.highlightedTextColor
            }

            MouseArea {
                id: grab
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: compact.vertical ? Qt.SizeVerCursor : Qt.SizeHorCursor
                property real startPos: 0
                property real startLength: 0
                // The pointer position along the panel. Using the pointer, not the handle, keeps the
                // drag steady even though the handle moves as the strip changes length.
                function pointerPos(mouse) {
                    var g = mapToGlobal(mouse.x, mouse.y)
                    return compact.vertical ? g.y : g.x
                }
                onPressed: function (mouse) {
                    startPos = pointerPos(mouse)
                    startLength = compact.vertical ? layout.implicitHeight : layout.implicitWidth
                    root.beginDrag(startLength)
                }
                onPositionChanged: function (mouse) {
                    if (pressed) root.dragTo(startLength, startPos, pointerPos(mouse))
                }
                onReleased: root.finishDrag()
                onCanceled: root.cancelDrag()
                onDoubleClicked: root.resetLength()
            }
        }

        // Live readout while dragging.
        Rectangle {
            visible: root.dragging
            z: 60
            x: (compact.width - width) / 2
            y: 0
            width: readout.implicitWidth + Kirigami.Units.smallSpacing * 2
            height: readout.implicitHeight
            radius: 3
            color: Kirigami.Theme.backgroundColor
            opacity: 0.92
            PlasmaComponents.Label {
                id: readout
                anchors.centerIn: parent
                font.pixelSize: 10
                text: root.lengthReadout()
            }
        }
    }

    // ---- popup ----
    // Built from the user's order: one block per stat (its rows plus its graph). The name column has
    // a fixed width, so values line up from one block to the next.
    TextMetrics { id: mPopupLabel; font: Kirigami.Theme.defaultFont; text: "CPU temp (max core)" }
    readonly property real popupLabelWidth: mPopupLabel.width

    function popupShown(id) {
        switch (id) {
        case "cpu":  return popupCpu
        case "ram":  return popupMemory
        case "temp": return popupTempAvg || popupTempMax || popupCores
        case "freq": return popupFreq
        case "net":  return popupNet
        case "bat":  return popupBatShown
        case "fan":  return popupFanShown
        }
        return false
    }
    function anyPopupShown() {
        for (var i = 0; i < statOrder.length; ++i) if (popupShown(statOrder[i])) return true
        return false
    }

    // One row: a name, then a bold value.
    component PopupRow: RowLayout {
        id: popupRow
        property string name
        property string value
        property color valueColor: Kirigami.Theme.textColor
        property bool fanIcon: false                        // the spinning fan icon before the value
        spacing: Kirigami.Units.largeSpacing
        PlasmaComponents.Label { text: popupRow.name; Layout.preferredWidth: root.popupLabelWidth }
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Loader {
                active: popupRow.fanIcon
                visible: active
                sourceComponent: FanIcon {
                    level: root.fanLevel
                    animate: root.fanAnimate
                }
            }
            PlasmaComponents.Label { text: popupRow.value; font.bold: true; color: popupRow.valueColor }
        }
    }
    // A graph under a stat's rows. Its data, scale and colours come from the same helpers the panel uses.
    component PopupGraph: Spark {
        id: pg
        property string statId
        property bool wanted: true                          // an extra condition (the temperature graph needs its row)
        readonly property bool on: wanted && root.statPopupGraph(statId)
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 2
        visible: on && history !== null
        history: on ? root.statHistory(statId) : null
        history2: on ? root.statHistory2(statId) : null
        yFrom: root.statYFrom(statId)
        yTo: root.statYTo(statId)
        lineColor: root.statLineColor(statId)
    }

    // The values a popup row reads: every sensor of a plain stat (popup-only ones included), the live values of
    // the others. Read inside the calling binding, so QML re-evaluates it.
    function popupVals(id) {
        var m = M.byId(id)
        if (m.source) return statVals(id)
        var vals = {}
        for (var name in m.sensors) vals[name] = sensorValue(id, name)
        return vals
    }
    // The inputs of M.popupRowShown / M.popupGraphShown for a stat.
    function popupFlags(id) {
        var f = sensorFlags(id)
        f.available = { hasBattery: hasBattery, hasFan: hasFan }
        return f
    }
    function popupRowColor(id, row) {
        if (row.alert === "panel") return statTextColor(id)
        if (typeof row.alert === "function")
            return row.alert(popupVals(id), limitCtx) ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        return Kirigami.Theme.textColor
    }

    // One registry row of a stat's popup.
    component StatRow: PopupRow {
        required property var modelData
        property string statId
        visible: M.popupRowShown(modelData, root.popupFlags(statId))
        name: modelData.label
        value: M.render(modelData.value, root.popupVals(statId), root.textCtx)
        valueColor: root.popupRowColor(statId, modelData)
        fanIcon: modelData.decoration === "fanIcon"
    }
    // The block of a stat made only of registry rows and a graph (every stat but the battery so far).
    // Its stat id comes from the Loader that holds it.
    Component {
        id: statBlock
        ColumnLayout {
            id: blk
            readonly property string statId: parent && parent.blockStatId ? parent.blockStatId : ""
            Repeater {
                model: blk.statId ? M.byId(blk.statId).popup.rows.slice(0, M.popupRowsBeforeGraph(M.byId(blk.statId))) : []
                delegate: StatRow { statId: blk.statId }
            }
            PopupGraph {
                statId: blk.statId
                wanted: blk.statId !== "" && M.popupGraphShown(M.byId(blk.statId), root.popupFlags(blk.statId))
            }
            Repeater {
                model: blk.statId ? M.byId(blk.statId).popup.rows.slice(M.popupRowsBeforeGraph(M.byId(blk.statId))) : []
                delegate: StatRow { statId: blk.statId }
            }
            Loader {
                readonly property string blockStatId: blk.statId
                active: blk.statId !== "" && !!M.byId(blk.statId).popup.repeat
                        && M.flagOn(M.byId(blk.statId).popup.repeat.when, root.popupFlags(blk.statId))
                visible: active && item !== null && item.count > 0
                Layout.fillWidth: true
                sourceComponent: repeatBlock
            }
        }
    }

    function popupBlock(id) {
        switch (id) {
        case "bat":  return batBlock
        }
        return M.byId(id) ? statBlock : null
    }

    Component {
        id: batBlock
        ColumnLayout {
            PopupRow {
                name: "Battery"
                value: root.batRowText()
                valueColor: root.statTextColor("bat")
            }
            // One line per battery, only when "each battery separately" is chosen.
            Repeater {
                model: (root.batSeparate && root.batterySources.length > 1) ? root.batterySources : []
                delegate: PlasmaComponents.Label {
                    required property var modelData
                    readonly property var d: root.batteryData(modelData)
                    Layout.leftMargin: Kirigami.Units.gridUnit
                    opacity: 0.85
                    text: (d["Pretty Name"] ? d["Pretty Name"] : modelData) + ":  " + root.pct(d["Percent"])
                          + "  (" + root.wh(d["Energy"]) + ")  ·  health " + root.pct(d["Capacity"])
                          + (d["State"] === "Charging" ? "  ↑" : (d["State"] === "Discharging" ? "  ↓" : ""))
                }
            }
            PopupRow {
                visible: root.batState !== 0
                name: root.batState > 0 ? "Charging" : "Discharging"
                value: root.batTimeText() !== "" ? root.batTimeText() + (root.batState > 0 ? " to full" : " left") : "estimating…"
            }
            PopupGraph { statId: "bat" }
        }
    }
    // The per-item lines of a stat's popup (the temperature of each core): a header and a two-column grid, one
    // line per item. Its sensors only exist while the popup is open (one per delegate).
    Component {
        id: repeatBlock
        ColumnLayout {
            id: rep
            readonly property string statId: parent && parent.blockStatId ? parent.blockStatId : ""
            readonly property var spec: statId ? M.byId(statId).popup.repeat : null
            readonly property int count: spec && root.isNum(root.coreCount) ? Number(root.coreCount) : 0
            PlasmaComponents.Label {
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: rep.spec ? rep.spec.header : ""
                font.bold: true
            }
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Kirigami.Units.gridUnit * 2
                rowSpacing: 0

                Repeater {
                    model: rep.count

                    delegate: RowLayout {
                        id: item
                        required property int index
                        Layout.fillWidth: true

                        Sensors.Sensor {
                            id: itemSensor
                            sensorId: rep.spec.sensor.replace("{n}", item.index)
                            updateRateLimit: root.refreshMs
                        }
                        readonly property bool hot: rep.spec.alert({ value: itemSensor.value }, root.limitCtx)

                        PlasmaComponents.Label {
                            text: rep.spec.label.replace("{n}", item.index + 1)
                            Layout.fillWidth: true
                        }
                        PlasmaComponents.Label {
                            text: M.render(rep.spec.value, { value: itemSensor.value }, root.textCtx)
                            font.bold: true
                            color: item.hot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                        }
                    }
                }
            }
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14

        Repeater {
            model: root.statOrder
            delegate: Loader {
                required property string modelData
                Layout.fillWidth: true
                readonly property string blockStatId: modelData
                active: root.popupShown(modelData)
                visible: active
                sourceComponent: root.popupBlock(modelData)
            }
        }

        PlasmaComponents.Label {
            visible: !root.anyPopupShown()
            text: "Nothing to show. Enable items under Configure > Metrics."
            opacity: 0.7
        }
    }
}
