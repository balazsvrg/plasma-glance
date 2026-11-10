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

    // ---- sensors (IDs verified with `kstatsviewer --list`) ----
    Sensors.Sensor { id: cpuUsage;   sensorId: "cpu/all/usage";                updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memPercent; sensorId: "memory/physical/usedPercent";  updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memUsed;    sensorId: "memory/physical/used";         updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memTotal;   sensorId: "memory/physical/total";        updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: tempAvg;    sensorId: "cpu/all/averageTemperature";   updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: tempMax;    sensorId: "cpu/all/maximumTemperature";   updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: freqAvg;    sensorId: "cpu/all/averageFrequency";     updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: freqMin;    sensorId: "cpu/all/minimumFrequency";     updateRateLimit: root.refreshMs }
    Sensors.Sensor {
        id: freqMax
        sensorId: "cpu/all/maximumFrequency"
        updateRateLimit: root.refreshMs
        // The hardware maximum is not a sensor, so the frequency graph's scale
        // grows to the highest value seen (never below 1 GHz).
        onValueChanged: if (root.isNum(value) && value > root.freqPeak) root.freqPeak = value
    }
    property real freqPeak: 1000
    // Network, all interfaces combined (bytes per second; totals in bytes since boot).
    Sensors.Sensor {
        id: netDown
        sensorId: "network/all/download"
        updateRateLimit: root.refreshMs
        onValueChanged: root.trackNetPeak(value)
    }
    Sensors.Sensor {
        id: netUp
        sensorId: "network/all/upload"
        updateRateLimit: root.refreshMs
        onValueChanged: root.trackNetPeak(value)
    }
    Sensors.Sensor { id: netDownTotal; sensorId: "network/all/totalDownload"; updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: netUpTotal;   sensorId: "network/all/totalUpload";   updateRateLimit: root.refreshMs }
    // Network graph scale: follows the recent peak and decays slowly, never below 100 KB/s.
    property real netPeak: 100000
    function trackNetPeak(v) {
        if (!isNum(v)) return
        netPeak = Math.max(100000, Number(v), netPeak * 0.995)
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
    function syncBatteryCount() {
        var n = hasBattery ? batterySources.length : 0
        if (Plasmoid.configuration.batteryCount !== n) Plasmoid.configuration.batteryCount = n
    }
    onHasBatteryChanged: syncBatteryCount()
    onBatterySourcesChanged: syncBatteryCount()

    readonly property var batPercent: isNum(batterySummary["Percent"]) ? Number(batterySummary["Percent"]) : undefined
    readonly property int batState: batterySummary["State"] === "Charging" ? 1
                                    : (batterySummary["State"] === "Discharging" ? -1 : 0)
    readonly property bool batLow: isNum(batPercent) && batPercent < 15 && batState <= 0
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
        signal found(var ids)

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
            found(ids)
        }
    }

    // Alive only while a fan stat is shown, plus once at start-up so the settings
    // pages know whether a fan exists.
    Loader {
        active: root.fanWanted || !root.fanDiscoveryDone
        sourceComponent: FanDiscovery {
            onFound: function (ids) {
                if (JSON.stringify(ids) !== JSON.stringify(root.fanIds))
                    root.fanIds = ids
                root.fanDiscoveryDone = true
                if (Plasmoid.configuration.fanCount !== ids.length)
                    Plasmoid.configuration.fanCount = ids.length
            }
        }
    }

    property var fanItems: []
    Repeater {
        id: fanRepeater
        model: root.fanWanted ? root.fanIds : []
        onItemAdded: root.fanItems = collectFans()
        onItemRemoved: root.fanItems = collectFans()
        function collectFans() {
            var items = []
            for (var i = 0; i < count; ++i) { var it = itemAt(i); if (it) items.push(it) }
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
    // Graph scale: grows to the highest RPM seen, never below 3000.
    property real fanPeak: 3000
    onFanRpmChanged: if (isNum(fanRpm) && Number(fanRpm) > fanPeak) fanPeak = Number(fanRpm)
    QtObject { id: fanSensor; readonly property var value: root.fanRpm }

    // Number of per-core temperature sensors (cpu/cpuN/temperature, N = 0..count-1).
    Sensors.Sensor { id: coreCount;  sensorId: "cpu/all/coreCount" }

    // ---- graph history ----
    // Each stat has its own history. It is collected only while a graph that
    // shows that stat is enabled, and it starts once the stat's sensor has
    // reported a real number (so the history never begins with fake zeros).
    readonly property int styleBehind: 1
    readonly property int styleInline: 2   // keep in sync with the dropdown in configGraphs.qml
    readonly property int panelGraphStyle: Plasmoid.configuration.panelGraphStyle
    readonly property bool graphInline: panelGraphStyle === styleInline   // anything else (incl. an old 0) is "behind"
    // Which stats get a graph: gp* in the panel, gd* in the popup (Metrics tab).
    readonly property bool gpCpu:  Plasmoid.configuration.graphPanelCpu
    readonly property bool gpRam:  Plasmoid.configuration.graphPanelRam
    readonly property bool gpTemp: Plasmoid.configuration.graphPanelTemp
    readonly property bool gpFreq: Plasmoid.configuration.graphPanelFreq
    readonly property bool gpNet:  Plasmoid.configuration.graphPanelNet
    readonly property bool gpBat:  Plasmoid.configuration.graphPanelBat
    readonly property bool gpFan:  Plasmoid.configuration.graphPanelFan
    readonly property bool gdCpu:  Plasmoid.configuration.graphPopupCpu
    readonly property bool gdRam:  Plasmoid.configuration.graphPopupRam
    readonly property bool gdTemp: Plasmoid.configuration.graphPopupTemp
    readonly property bool gdFreq: Plasmoid.configuration.graphPopupFreq
    readonly property bool gdNet:  Plasmoid.configuration.graphPopupNet
    readonly property bool gdBat:  Plasmoid.configuration.graphPopupBat
    readonly property bool gdFan:  Plasmoid.configuration.graphPopupFan
    readonly property int historySeconds: Math.min(300, Math.max(30, Plasmoid.configuration.historySeconds))
    readonly property int historyLen: Math.max(2, Math.round(historySeconds * 1000 / refreshMs))
    readonly property real tempYMin: 20                               // temperature graph scale: tempYMin .. tempYMax
    readonly property real tempYMax: Math.max(100, warnTempC + 10)

    component History: Loader {
        id: hist
        property var sensor
        property bool wanted: false
        property bool ready: false          // latched once the sensor has reported a number
        readonly property var historySource: item ? item.history : null
        readonly property bool numeric: root.isNum(sensor.value)

        onNumericChanged: if (numeric) ready = true
        Component.onCompleted: if (numeric) ready = true

        active: wanted && ready
        sourceComponent: Item {
            readonly property var history: h
            Charts.HistoryProxySource {
                id: h
                source: Charts.SingleValueSource { value: hist.sensor.value }
                maximumHistory: root.historyLen
                interval: root.refreshMs
                fillMode: Charts.HistoryProxySource.DoNotFill
            }
        }
    }

    History { id: cpuHistory;  sensor: cpuUsage;  wanted: (root.gpCpu && root.showCpu)  || (root.gdCpu && root.popupCpu) }
    History { id: ramHistory;  sensor: memPercent; wanted: (root.gpRam && root.showRam)  || (root.gdRam && root.popupMemory) }
    History { id: tempHistory; sensor: tempAvg;   wanted: (root.gpTemp && root.showTemp) || (root.gdTemp && root.popupTempAvg) }
    History { id: freqHistory; sensor: freqAvg;   wanted: (root.gpFreq && root.showFreq) || (root.gdFreq && root.popupFreq) }
    History { id: netDownHistory; sensor: netDown; wanted: (root.gpNet && root.showNet) || (root.gdNet && root.popupNet) }
    History { id: netUpHistory;   sensor: netUp;   wanted: (root.gpNet && root.showNet) || (root.gdNet && root.popupNet) }
    History { id: fanHistory;     sensor: fanSensor; wanted: (root.gpFan && root.fanShown) || (root.gdFan && root.popupFanShown) }
    History { id: batHistory;     sensor: batSensor; wanted: (root.gpBat && root.batShown) || (root.gdBat && root.popupBatShown) }

    readonly property var cpuHist:  cpuHistory.historySource
    readonly property var ramHist:  ramHistory.historySource
    readonly property var tempHist: tempHistory.historySource
    readonly property var freqHist: freqHistory.historySource
    readonly property var netDownHist: netDownHistory.historySource
    readonly property var netUpHist: netUpHistory.historySource
    readonly property var batHist: batHistory.historySource
    readonly property var fanHist: fanHistory.historySource

    // One small line graph; used by the popup and (next) the panel.
    component Spark: Charts.LineChart {
        id: spark
        property var history: null
        property var history2: null          // optional second line (e.g. upload)
        property real yFrom: 0
        property real yTo: 100
        property color lineColor: Kirigami.Theme.highlightColor
        property color lineColor2: Kirigami.Theme.positiveTextColor

        valueSources: history ? (history2 ? [history, history2] : [history]) : []
        colorSource: Charts.ArraySource { array: [spark.lineColor, spark.lineColor2] }
        xRange { automatic: true }            // spans the samples collected so far
        yRange { from: spark.yFrom; to: spark.yTo; automatic: false }
        direction: Charts.XYChart.ZeroAtEnd   // newest sample on the right
        lineWidth: 1.5
        fillOpacity: 0.15
        interpolate: false
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
                fanIcon.frame = (fanIcon.frame + 1) % 1000
            }
        }
    }

    // ---- formatting helpers ----
    // Accepts any real numeric value; rejects undefined, null, "" and NaN so a
    // missing sensor shows "--" instead of a fake 0.
    function isNum(v) {
        return v !== undefined && v !== null && v !== "" && isFinite(Number(v))
    }
    function pct(v)   { return isNum(v) ? Math.round(v) + "%" : "--%" }
    function temp(v) {
        var unit = useF ? "°F" : "°C"
        if (!isNum(v)) return "--" + unit
        return Math.round(useF ? v * 9 / 5 + 32 : v) + unit
    }
    function gib(v)   { return isNum(v) ? (v / 1073741824).toFixed(1) + " GiB" : "-- GiB" }
    function rpmText(v) { return isNum(v) ? Math.round(Number(v)) + " RPM" : "-- RPM" }
    function wh(v) { return isNum(v) ? Number(v).toFixed(1) + " Wh" : "-- Wh" }
    function batArrow() { return batState > 0 ? " ↑" : (batState < 0 ? " ↓" : "") }
    function batText() { return pct(batPercent) + batArrow() }
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
    // Network rates arrive in bytes/s. Decimal units: 1 KB = 1000 B (bits: x8).
    function rateParts(v) {
        var x = netBits ? Number(v) * 8 : Number(v)
        var units = netBits ? ["b", "Kb", "Mb", "Gb"] : ["B", "KB", "MB", "GB"]
        var i = 0
        while (x >= 1000 && i < 3) { x /= 1000; i++ }
        return { n: (x >= 10 || i === 0) ? String(Math.round(x)) : x.toFixed(1), unit: units[i] }
    }
    function rate(v)      { if (!isNum(v)) return "--"; var p = rateParts(v); return p.n + " " + p.unit + "/s" }
    function rateShort(v) { if (!isNum(v)) return "--"; var p = rateParts(v); return p.n + p.unit.charAt(0) }
    function netText()      { return "↓" + rate(netDown.value) + " ↑" + rate(netUp.value) }
    function bytesText(v) {
        if (!isNum(v)) return "--"
        var x = Number(v)
        if (x >= 1e9) return (x / 1e9).toFixed(1) + " GB"
        if (x >= 1e6) return (x / 1e6).toFixed(1) + " MB"
        return Math.round(x / 1e3) + " KB"
    }
    // CPU frequency arrives in MHz; show GHz from 1000 MHz up.
    function ghzNumber(v) { return isNum(v) ? (v / 1000).toFixed(1) : "--" }
    function freq(v) {
        if (!isNum(v)) return "-- GHz"
        return v >= 1000 ? ghzNumber(v) + " GHz" : Math.round(v) + " MHz"
    }

    // Each temperature is highlighted by its own value, so the colour always
    // matches the number shown next to it.
    readonly property bool avgHot: isNum(tempAvg.value) && tempAvg.value >= warnTempC
    readonly property bool tempHot: isNum(tempMax.value) && tempMax.value >= warnTempC

    function tooltipText() {
        var parts = []
        if (showCpu)  parts.push("CPU " + pct(cpuUsage.value))
        if (showRam)  parts.push("RAM " + pct(memPercent.value))
        if (showTemp) parts.push(temp(tempAvg.value))
        if (showFreq) parts.push(freq(freqAvg.value))
        if (showNet)  parts.push(netText())
        if (batShown) parts.push("BAT " + batText())
        if (fanShown) parts.push(rpmText(fanRpm))
        return parts.join(" · ")
    }

    // ---- maximum length ----
    // Along the panel direction: width on a horizontal panel, height on a vertical one.
    // When the strip would be longer than the limit it saves space in steps and stops at
    // the first step that fits:
    //   0  full text, graphs as chosen
    //   1  inline graphs become behind-text graphs (those take no length)
    //   2  compact text (CPU 8% -> C 8%, 2.2 GHz -> 2.2G, ...), still readable
    //   3  tight spacing
    // If even that is too long, stats are dropped from the end (Fan, Battery, Net, Freq,
    // Temp, RAM) until it fits. CPU is never dropped. The tooltip always lists everything.
    // The saved limit (px, 0 = no limit), or the live value while the edge handle is being dragged.
    readonly property int maxLength: dragging ? dragMax() : Plasmoid.configuration.maxLength
    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property var statOrder: ["cpu", "ram", "temp", "freq", "net", "bat", "fan"]

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
    function statGraph(id) {
        switch (id) {
        case "cpu":  return gpCpu
        case "ram":  return gpRam
        case "temp": return gpTemp
        case "freq": return gpFreq
        case "net":  return gpNet
        case "bat":  return gpBat
        case "fan":  return gpFan
        }
        return false
    }
    function shownIds() {
        var ids = []
        for (var i = 0; i < statOrder.length; ++i) if (statShown(statOrder[i])) ids.push(statOrder[i])
        return ids
    }

    // Widest possible text per stat, so the strip does not resize when a number gains a digit.
    TextMetrics { id: mCpu;   font: Kirigami.Theme.defaultFont; text: "CPU 100%" }
    TextMetrics { id: mCpuC;  font: Kirigami.Theme.defaultFont; text: "C 100%" }
    TextMetrics { id: mRam;   font: Kirigami.Theme.defaultFont; text: "RAM 100%" }
    TextMetrics { id: mRamC;  font: Kirigami.Theme.defaultFont; text: "R 100%" }
    TextMetrics { id: mTemp;  font: Kirigami.Theme.defaultFont; text: root.useF ? "212°F" : "100°C" }
    TextMetrics { id: mTempC; font: Kirigami.Theme.defaultFont; text: root.useF ? "212°" : "100°" }
    TextMetrics { id: mFreq;  font: Kirigami.Theme.defaultFont; text: "9.9 GHz" }
    TextMetrics { id: mFreqC; font: Kirigami.Theme.defaultFont; text: "9.9G" }
    TextMetrics { id: mNet;   font: Kirigami.Theme.defaultFont; text: "↓999 MB/s ↑999 MB/s" }
    TextMetrics { id: mNetC;  font: Kirigami.Theme.defaultFont; text: "↓999M ↑999M" }
    TextMetrics { id: mBat;   font: Kirigami.Theme.defaultFont; text: "BAT 100% ↓" }
    TextMetrics { id: mBatC;  font: Kirigami.Theme.defaultFont; text: "B 100%↓" }
    TextMetrics { id: mFan;   font: Kirigami.Theme.defaultFont; text: "9999 RPM" }
    TextMetrics { id: mFanC;  font: Kirigami.Theme.defaultFont; text: "9999" }
    TextMetrics { id: mLine;  font: Kirigami.Theme.defaultFont; text: "Ag" }       // one line of text

    function reservedWidth(id, compact) {
        switch (id) {
        case "cpu":  return compact ? mCpuC.width  : mCpu.width
        case "ram":  return compact ? mRamC.width  : mRam.width
        case "temp": return compact ? mTempC.width : mTemp.width
        case "freq": return compact ? mFreqC.width : mFreq.width
        case "net":  return compact ? mNetC.width  : mNet.width
        case "bat":  return compact ? mBatC.width  : mBat.width
        case "fan":  return compact ? mFanC.width  : mFan.width
        }
        return 0
    }

    function tempShort(v) {
        if (!isNum(v)) return "--°"
        return Math.round(useF ? v * 9 / 5 + 32 : v) + "°"
    }
    function freqShort(v) {
        if (!isNum(v)) return "--G"
        return v >= 1000 ? (v / 1000).toFixed(1) + "G" : Math.round(v) + "M"
    }
    function batArrowShort() { return batState > 0 ? "↑" : (batState < 0 ? "↓" : "") }
    function rpmNumber(v) { return isNum(v) ? String(Math.round(Number(v))) : "--" }

    // The text of a stat in the panel, for the current step (compact or full) and orientation.
    function statText(id, compact, vert) {
        switch (id) {
        case "cpu":
            return compact ? "C " + pct(cpuUsage.value) : (vert ? "CPU\n" : "CPU ") + pct(cpuUsage.value)
        case "ram":
            return compact ? "R " + pct(memPercent.value) : (vert ? "RAM\n" : "RAM ") + pct(memPercent.value)
        case "temp":
            return compact ? tempShort(tempAvg.value) : (vert ? "Temp\n" : "") + temp(tempAvg.value)
        case "freq":
            return compact ? freqShort(freqAvg.value) : (vert ? "Freq\n" : "") + freq(freqAvg.value)
        case "net":
            if (compact) return "↓" + rateShort(netDown.value) + (vert ? "\n↑" : " ↑") + rateShort(netUp.value)
            return vert ? "Net\n↓" + rateShort(netDown.value) + "\n↑" + rateShort(netUp.value) : netText()
        case "bat":
            return compact ? "B " + pct(batPercent) + batArrowShort() : (vert ? "Bat\n" : "BAT ") + batText()
        case "fan":
            return compact ? rpmNumber(fanRpm) : (vert ? "Fan\n" + rpmNumber(fanRpm) : rpmText(fanRpm))
        }
        return ""
    }

    // Space one stat takes at a given step (width when horizontal, height when vertical).
    function cellLength(id, level) {
        var compact = level >= 2
        var inlineGraph = level === 0 && graphInline && statGraph(id)
        var gap = Kirigami.Units.smallSpacing
        if (!vertical) {
            var w = reservedWidth(id, compact)
            if (id === "fan") w += Kirigami.Units.iconSizes.smallMedium + gap
            if (inlineGraph) w += gap + Kirigami.Units.gridUnit * 4
            return w
        }
        var lines = (id === "net" ? 2 : 1) + (compact ? 0 : 1)          // value lines (+ caption line)
        var h = lines * mLine.height
        if (id === "fan") h += Kirigami.Units.iconSizes.smallMedium
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
        // a 1 px divider and two gaps between stats; rounded up so rounding never lets it exceed the limit
        return Math.ceil(total + (n - 1) * (1 + 2 * gap))
    }
    function computeFit() {
        var ids = shownIds()
        if (maxLength <= 0 || ids.length === 0) return { level: 0, drop: 0 }
        for (var level = 0; level <= 3; ++level)
            if (stripLength(level, 0) <= maxLength) return { level: level, drop: 0 }
        for (var drop = 1; drop < ids.length; ++drop)
            if (stripLength(3, drop) <= maxLength) return { level: 3, drop: drop }
        return { level: 3, drop: ids.length - 1 }                         // only the first stat is left
    }
    readonly property var fit: computeFit()
    readonly property int lengthLevel: fit.level
    readonly property bool textCompact: lengthLevel >= 2
    readonly property var droppedIds: shownIds().slice(shownIds().length - fit.drop)

    // ---- adjusting the limit with the mouse ----
    // Right-click > "Adjust length with the mouse" shows a handle on the strip's far edge
    // (right edge, or bottom edge on a vertical panel). Dragging it resizes the strip live;
    // the value is saved on release. Dragging out to the full length means "no limit".
    property bool adjusting: false           // handle visible
    property bool dragging: false            // handle being dragged
    property real dragLength: 0              // strip length under the mouse, px
    function dragMax() {
        var v = Math.max(20, Math.round(dragLength / 5) * 5)                 // snap to 5 px
        return v >= stripLength(0, 0) ? 0 : v
    }
    function finishDrag() {
        if (!dragging) return
        var v = maxLength
        dragging = false
        Plasmoid.configuration.maxLength = v
    }
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

    function cellShown(id) { return statShown(id) && droppedIds.indexOf(id) < 0 }
    function anyCellBefore(id) {
        for (var i = 0; i < statOrder.length && statOrder[i] !== id; ++i)
            if (cellShown(statOrder[i])) return true
        return false
    }
    function anyCell() {
        for (var i = 0; i < statOrder.length; ++i) if (cellShown(statOrder[i])) return true
        return false
    }

    preferredRepresentation: compactRepresentation
    toolTipMainText: "System stats"
    toolTipSubText: tooltipText()

    compactRepresentation: MouseArea {
        id: compact
        onClicked: root.expanded = !root.expanded

        readonly property bool vertical: root.vertical

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
            property int fanLevel: 0
            property color textColor: Kirigami.Theme.textColor
            property var history: null
            property var history2: null
            property real yFrom: 0
            property real yTo: 100
            property color lineColor: Kirigami.Theme.highlightColor

            property bool graphOn: false                       // this stat's panel graph toggle
            readonly property bool hasGraph: graphOn && history !== null
            // Inline graphs take length, so they turn into behind-text graphs when space is short.
            readonly property bool behind: hasGraph && (!root.graphInline || root.lengthLevel >= 1)
            readonly property bool inline: hasGraph && root.graphInline && root.lengthLevel === 0

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
                anchors.fill: parent
                columns: compact.vertical ? 1 : (cell.fan ? 3 : 2)
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: 0

                FanIcon {
                    visible: cell.fan
                    Layout.alignment: Qt.AlignCenter
                    level: cell.fanLevel
                    animate: root.fanAnimate
                    color: cell.textColor
                }
                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignCenter
                    Layout.minimumWidth: compact.vertical ? 0 : root.reservedWidth(cell.statId, root.textCompact)
                    Layout.preferredWidth: compact.vertical ? -1 : root.reservedWidth(cell.statId, root.textCompact)
                    Layout.fillWidth: compact.vertical
                    horizontalAlignment: Text.AlignHCenter
                    fontSizeMode: compact.vertical ? Text.HorizontalFit : Text.FixedSize
                    minimumPixelSize: 8
                    text: root.statText(cell.statId, root.textCompact, compact.vertical)
                    color: cell.textColor
                }
                Spark {
                    visible: cell.inline
                    Layout.alignment: Qt.AlignCenter
                    Layout.fillWidth: compact.vertical
                    Layout.preferredWidth: compact.vertical ? -1 : Kirigami.Units.gridUnit * 4
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
            columns: compact.vertical ? 1 : 13
            columnSpacing: root.spacingFor(root.lengthLevel)
            rowSpacing: root.rowSpacingFor(root.lengthLevel)

            MetricCell {
                statId: "cpu"
                visible: root.cellShown("cpu")
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                graphOn: root.gpCpu
                history: root.cpuHist
            }
            Divider { visible: root.cellShown("ram") && root.anyCellBefore("ram") }
            MetricCell {
                statId: "ram"
                visible: root.cellShown("ram")
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                graphOn: root.gpRam
                history: root.ramHist
            }
            Divider { visible: root.cellShown("temp") && root.anyCellBefore("temp") }
            MetricCell {
                statId: "temp"
                visible: root.cellShown("temp")
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                textColor: root.avgHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                graphOn: root.gpTemp
                history: root.tempHist
                yFrom: root.tempYMin
                yTo: root.tempYMax
                lineColor: root.avgHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
            }
            Divider { visible: root.cellShown("freq") && root.anyCellBefore("freq") }
            MetricCell {
                statId: "freq"
                visible: root.cellShown("freq")
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                graphOn: root.gpFreq
                history: root.freqHist
                yTo: root.freqPeak
            }
            Divider { visible: root.cellShown("net") && root.anyCellBefore("net") }
            MetricCell {
                statId: "net"
                visible: root.cellShown("net")
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                graphOn: root.gpNet
                history: root.netDownHist
                history2: root.netUpHist
                yTo: root.netPeak
            }
            Divider { visible: root.cellShown("bat") && root.anyCellBefore("bat") }
            MetricCell {
                statId: "bat"
                visible: root.cellShown("bat")
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                textColor: root.batLow ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                graphOn: root.gpBat
                history: root.batHist
                lineColor: root.batLow ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
            }
            Divider { visible: root.cellShown("fan") && root.anyCellBefore("fan") }
            MetricCell {
                statId: "fan"
                visible: root.cellShown("fan")
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                fanLevel: root.fanLevel
                graphOn: root.gpFan
                history: root.fanHist
                yTo: root.fanPeak
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
            x: compact.vertical ? 0 : compact.width - width
            y: compact.vertical ? compact.height - height : 0
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
                    root.dragLength = startLength
                    root.dragging = true
                }
                onPositionChanged: function (mouse) {
                    if (pressed) root.dragLength = startLength + (pointerPos(mouse) - startPos)
                }
                onReleased: root.finishDrag()
                onCanceled: root.finishDrag()
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

    fullRepresentation: GridLayout {
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14

        PlasmaComponents.Label { visible: root.popupCpu; text: "CPU usage" }
        PlasmaComponents.Label { visible: root.popupCpu; text: root.pct(cpuUsage.value); font.bold: true }

        Spark {
            visible: root.gdCpu && root.popupCpu && root.cpuHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.gdCpu && root.popupCpu) ? root.cpuHist : null
        }

        PlasmaComponents.Label { visible: root.popupMemory; text: "Memory" }
        PlasmaComponents.Label {
            visible: root.popupMemory
            text: root.gib(memUsed.value) + " / " + root.gib(memTotal.value)
                  + " (" + root.pct(memPercent.value) + ")"
            font.bold: true
        }

        Spark {
            visible: root.gdRam && root.popupMemory && root.ramHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.gdRam && root.popupMemory) ? root.ramHist : null
        }

        PlasmaComponents.Label { visible: root.popupFreq; text: "CPU frequency" }
        PlasmaComponents.Label { visible: root.popupFreq; text: root.freq(freqAvg.value); font.bold: true }

        PlasmaComponents.Label { visible: root.popupFreq; text: "Min / max" }
        PlasmaComponents.Label {
            visible: root.popupFreq
            text: root.ghzNumber(freqMin.value) + " / " + root.ghzNumber(freqMax.value) + " GHz"
            font.bold: true
        }

        Spark {
            visible: root.gdFreq && root.popupFreq && root.freqHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.gdFreq && root.popupFreq) ? root.freqHist : null
            yTo: root.freqPeak
        }

        PlasmaComponents.Label { visible: root.popupNet; text: "Download" }
        PlasmaComponents.Label {
            visible: root.popupNet
            text: root.rate(netDown.value) + "  (" + root.bytesText(netDownTotal.value) + " total)"
            font.bold: true
        }

        PlasmaComponents.Label { visible: root.popupNet; text: "Upload" }
        PlasmaComponents.Label {
            visible: root.popupNet
            text: root.rate(netUp.value) + "  (" + root.bytesText(netUpTotal.value) + " total)"
            font.bold: true
        }

        Spark {
            visible: root.gdNet && root.popupNet && root.netDownHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.gdNet && root.popupNet) ? root.netDownHist : null
            history2: (root.gdNet && root.popupNet) ? root.netUpHist : null
            yTo: root.netPeak
        }

        PlasmaComponents.Label { visible: root.popupBatShown; text: "Battery" }
        PlasmaComponents.Label {
            visible: root.popupBatShown
            text: root.batText() + (root.isNum(root.batEnergyTotal()) ? "  (" + root.wh(root.batEnergyTotal()) + ")" : "")
            font.bold: true
            color: root.batLow ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }

        // One line per battery, only when "each battery separately" is chosen.
        Repeater {
            model: (root.popupBatShown && root.batSeparate && root.batterySources.length > 1) ? root.batterySources : []
            delegate: PlasmaComponents.Label {
                required property var modelData
                readonly property var d: root.batteryData(modelData)
                Layout.columnSpan: 2
                Layout.leftMargin: Kirigami.Units.gridUnit
                opacity: 0.85
                text: (d["Pretty Name"] ? d["Pretty Name"] : modelData) + ":  " + root.pct(d["Percent"])
                      + "  (" + root.wh(d["Energy"]) + ")  ·  health " + root.pct(d["Capacity"])
                      + (d["State"] === "Charging" ? "  ↑" : (d["State"] === "Discharging" ? "  ↓" : ""))
            }
        }

        PlasmaComponents.Label { visible: root.popupBatShown && root.batState !== 0; text: root.batState > 0 ? "Charging" : "Discharging" }
        PlasmaComponents.Label {
            visible: root.popupBatShown && root.batState !== 0
            text: root.batTimeText() !== "" ? root.batTimeText() + (root.batState > 0 ? " to full" : " left") : "estimating…"
            font.bold: true
        }

        Spark {
            visible: root.gdBat && root.popupBatShown && root.batHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.gdBat && root.popupBatShown) ? root.batHist : null
            lineColor: root.batLow ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
        }

        PlasmaComponents.Label { visible: root.popupFanShown; text: "Fan" }
        RowLayout {
            visible: root.popupFanShown
            spacing: Kirigami.Units.smallSpacing
            FanIcon {
                level: root.fanLevel
                animate: root.fanAnimate
            }
            PlasmaComponents.Label { text: root.rpmText(root.fanRpm); font.bold: true }
        }

        Spark {
            visible: root.gdFan && root.popupFanShown && root.fanHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.gdFan && root.popupFanShown) ? root.fanHist : null
            yTo: root.fanPeak
        }

        PlasmaComponents.Label { visible: root.popupTempAvg; text: "CPU temp (avg)" }
        PlasmaComponents.Label {
            visible: root.popupTempAvg
            text: root.temp(tempAvg.value)
            font.bold: true
            color: root.avgHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }

        Spark {
            visible: root.gdTemp && root.popupTempAvg && root.tempHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.gdTemp && root.popupTempAvg) ? root.tempHist : null
            yFrom: root.tempYMin
            yTo: root.tempYMax
            lineColor: root.avgHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
        }

        PlasmaComponents.Label { visible: root.popupTempMax; text: "CPU temp (max core)" }
        PlasmaComponents.Label {
            visible: root.popupTempMax
            text: root.temp(tempMax.value)
            font.bold: true
            color: root.tempHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }

        // ---- per-core temperatures ----
        // Sensors are created per delegate, so they only exist while the popup is open.
        // Threads of one physical core (hyperthreading) report the same temperature.
        PlasmaComponents.Label {
            visible: root.popupCores && perCore.count > 0
            Layout.columnSpan: 2
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: "Per core"
            font.bold: true
        }

        GridLayout {
            visible: root.popupCores && perCore.count > 0
            Layout.columnSpan: 2
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Kirigami.Units.gridUnit * 2
            rowSpacing: 0

            Repeater {
                id: perCore
                model: root.popupCores && root.isNum(coreCount.value) ? Number(coreCount.value) : 0

                delegate: RowLayout {
                    id: coreRow
                    required property int index
                    Layout.fillWidth: true

                    Sensors.Sensor {
                        id: coreTemp
                        sensorId: "cpu/cpu" + coreRow.index + "/temperature"
                        updateRateLimit: root.refreshMs
                    }
                    readonly property bool hot: root.isNum(coreTemp.value) && coreTemp.value >= root.warnTempC

                    PlasmaComponents.Label {
                        text: "Core " + (coreRow.index + 1)
                        Layout.fillWidth: true
                    }
                    PlasmaComponents.Label {
                        text: root.temp(coreTemp.value)
                        font.bold: true
                        color: coreRow.hot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    }
                }
            }
        }

        PlasmaComponents.Label {
            visible: !root.popupCpu && !root.popupMemory && !root.popupTempAvg
                     && !root.popupTempMax && !root.popupCores && !root.popupFreq && !root.popupNet
                     && !root.popupBatShown && !root.popupFanShown
            Layout.columnSpan: 2
            text: "Nothing to show. Enable items under Configure > Metrics."
            opacity: 0.7
        }
    }
}
