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
    readonly property int styleOff: 0
    readonly property int styleBehind: 1
    readonly property int styleInline: 2   // keep in sync with the dropdown order in configGraphs.qml
    readonly property int panelGraphStyle: Plasmoid.configuration.panelGraphStyle
    readonly property bool popupGraphs: Plasmoid.configuration.popupGraphs
    readonly property bool panelGraphs: panelGraphStyle !== styleOff
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

    History { id: cpuHistory;  sensor: cpuUsage;  wanted: (root.panelGraphs && root.showCpu)  || (root.popupGraphs && root.popupCpu) }
    History { id: ramHistory;  sensor: memPercent; wanted: (root.panelGraphs && root.showRam)  || (root.popupGraphs && root.popupMemory) }
    History { id: tempHistory; sensor: tempAvg;   wanted: (root.panelGraphs && root.showTemp) || (root.popupGraphs && root.popupTempAvg) }
    History { id: freqHistory; sensor: freqAvg;   wanted: (root.panelGraphs && root.showFreq) || (root.popupGraphs && root.popupFreq) }
    History { id: netDownHistory; sensor: netDown; wanted: (root.panelGraphs && root.showNet) || (root.popupGraphs && root.popupNet) }
    History { id: netUpHistory;   sensor: netUp;   wanted: (root.panelGraphs && root.showNet) || (root.popupGraphs && root.popupNet) }
    History { id: fanHistory;     sensor: fanSensor; wanted: (root.panelGraphs && root.fanShown) || (root.popupGraphs && root.popupFanShown) }
    History { id: batHistory;     sensor: batSensor; wanted: (root.panelGraphs && root.batShown) || (root.popupGraphs && root.popupBatShown) }

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

    preferredRepresentation: compactRepresentation
    toolTipMainText: "System stats"
    toolTipSubText: tooltipText()

    compactRepresentation: MouseArea {
        id: compact
        onClicked: root.expanded = !root.expanded

        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical

        Layout.minimumWidth: vertical ? 0 : layout.implicitWidth
        Layout.minimumHeight: layout.implicitHeight
        Layout.preferredWidth: vertical ? -1 : layout.implicitWidth
        Layout.preferredHeight: layout.implicitHeight
        Layout.fillWidth: vertical

        // Reserve the widest possible text per column so the widget does not
        // resize (and jitter) when a value changes digit count.
        TextMetrics { id: cpuMetrics;  font: Kirigami.Theme.defaultFont; text: "CPU 100%" }
        TextMetrics { id: ramMetrics;  font: Kirigami.Theme.defaultFont; text: "RAM 100%" }
        TextMetrics { id: tempMetrics; font: Kirigami.Theme.defaultFont; text: root.useF ? "212°F" : "100°C" }
        TextMetrics { id: freqMetrics; font: Kirigami.Theme.defaultFont; text: "9.9 GHz" }
        TextMetrics { id: netMetrics;  font: Kirigami.Theme.defaultFont; text: "↓999 MB/s ↑999 MB/s" }
        TextMetrics { id: batMetrics;  font: Kirigami.Theme.defaultFont; text: "BAT 100% ↓" }
        TextMetrics { id: fanMetrics;  font: Kirigami.Theme.defaultFont; text: "9999 RPM" }

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

        // One metric in the panel: the text plus an optional graph, drawn either
        // behind the text (style 1) or after it (style 2; below it when vertical).
        component MetricCell: Item {
            id: cell
            property string caption                 // vertical layout: "CPU" over the value
            property string hPrefix: ""             // horizontal layout: "CPU " before the value
            property string valueText
            property string vValueText: ""          // optional different text for vertical panels
            property bool fan: false                // show the spinning fan icon before the text
            property int fanLevel: 0
            property real minLabelWidth: 0
            property color textColor: Kirigami.Theme.textColor
            property var history: null
            property var history2: null
            property real yFrom: 0
            property real yTo: 100
            property color lineColor: Kirigami.Theme.highlightColor

            readonly property bool hasGraph: root.panelGraphs && history !== null
            readonly property bool behind: hasGraph && root.panelGraphStyle === root.styleBehind
            readonly property bool inline: hasGraph && root.panelGraphStyle === root.styleInline

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
                    Layout.minimumWidth: compact.vertical ? 0 : cell.minLabelWidth
                    Layout.preferredWidth: compact.vertical ? -1 : cell.minLabelWidth
                    Layout.fillWidth: compact.vertical
                    horizontalAlignment: Text.AlignHCenter
                    fontSizeMode: compact.vertical ? Text.HorizontalFit : Text.FixedSize
                    minimumPixelSize: 8
                    text: compact.vertical ? cell.caption + "\n" + (cell.vValueText !== "" ? cell.vValueText : cell.valueText)
                                           : cell.hPrefix + cell.valueText
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
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            MetricCell {
                visible: root.showCpu
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                caption: "CPU"
                hPrefix: "CPU "
                valueText: root.pct(cpuUsage.value)
                minLabelWidth: cpuMetrics.width
                history: root.cpuHist
            }
            Divider { visible: root.showRam && root.showCpu }
            MetricCell {
                visible: root.showRam
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                caption: "RAM"
                hPrefix: "RAM "
                valueText: root.pct(memPercent.value)
                minLabelWidth: ramMetrics.width
                history: root.ramHist
            }
            Divider { visible: root.showTemp && (root.showCpu || root.showRam) }
            MetricCell {
                visible: root.showTemp
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                caption: "Temp"
                valueText: root.temp(tempAvg.value)
                minLabelWidth: tempMetrics.width
                textColor: root.avgHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                history: root.tempHist
                yFrom: root.tempYMin
                yTo: root.tempYMax
                lineColor: root.avgHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
            }
            Divider { visible: root.showFreq && (root.showCpu || root.showRam || root.showTemp) }
            MetricCell {
                visible: root.showFreq
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                caption: "Freq"
                valueText: root.freq(freqAvg.value)
                minLabelWidth: freqMetrics.width
                history: root.freqHist
                yTo: root.freqPeak
            }
            Divider { visible: root.showNet && (root.showCpu || root.showRam || root.showTemp || root.showFreq) }
            MetricCell {
                visible: root.showNet
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                caption: "Net"
                valueText: root.netText()
                vValueText: "↓" + root.rateShort(netDown.value) + "\n↑" + root.rateShort(netUp.value)
                minLabelWidth: netMetrics.width
                history: root.netDownHist
                history2: root.netUpHist
                yTo: root.netPeak
            }
            Divider { visible: root.batShown && (root.showCpu || root.showRam || root.showTemp || root.showFreq || root.showNet) }
            MetricCell {
                visible: root.batShown
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                caption: "Bat"
                hPrefix: "BAT "
                valueText: root.batText()
                minLabelWidth: batMetrics.width
                textColor: root.batLow ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                history: root.batHist
                lineColor: root.batLow ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
            }
            Divider { visible: root.fanShown && (root.showCpu || root.showRam || root.showTemp || root.showFreq || root.showNet || root.batShown) }
            MetricCell {
                visible: root.fanShown
                Layout.alignment: Qt.AlignCenter
                Layout.fillWidth: compact.vertical
                Layout.fillHeight: !compact.vertical
                caption: "Fan"
                valueText: root.rpmText(root.fanRpm)
                vValueText: root.isNum(root.fanRpm) ? String(Math.round(Number(root.fanRpm))) : "--"
                minLabelWidth: fanMetrics.width
                fan: true
                fanLevel: root.fanLevel
                history: root.fanHist
                yTo: root.fanPeak
            }
            PlasmaComponents.Label {
                visible: !root.showCpu && !root.showRam && !root.showTemp && !root.showFreq && !root.showNet && !root.batShown && !root.fanShown
                Layout.alignment: Qt.AlignCenter
                text: "–"
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
            visible: root.popupGraphs && root.popupCpu && root.cpuHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.popupGraphs && root.popupCpu) ? root.cpuHist : null
        }

        PlasmaComponents.Label { visible: root.popupMemory; text: "Memory" }
        PlasmaComponents.Label {
            visible: root.popupMemory
            text: root.gib(memUsed.value) + " / " + root.gib(memTotal.value)
                  + " (" + root.pct(memPercent.value) + ")"
            font.bold: true
        }

        Spark {
            visible: root.popupGraphs && root.popupMemory && root.ramHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.popupGraphs && root.popupMemory) ? root.ramHist : null
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
            visible: root.popupGraphs && root.popupFreq && root.freqHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.popupGraphs && root.popupFreq) ? root.freqHist : null
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
            visible: root.popupGraphs && root.popupNet && root.netDownHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.popupGraphs && root.popupNet) ? root.netDownHist : null
            history2: (root.popupGraphs && root.popupNet) ? root.netUpHist : null
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
            visible: root.popupGraphs && root.popupBatShown && root.batHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.popupGraphs && root.popupBatShown) ? root.batHist : null
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
            visible: root.popupGraphs && root.popupFanShown && root.fanHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.popupGraphs && root.popupFanShown) ? root.fanHist : null
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
            visible: root.popupGraphs && root.popupTempAvg && root.tempHist !== null
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 2
            history: (root.popupGraphs && root.popupTempAvg) ? root.tempHist : null
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
