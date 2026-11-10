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
    // Write a setting only when it changed (avoids needless config writes and change signals).
    function setCfg(key, value) {
        var c = Plasmoid.configuration
        if (c[key] !== value) c[key] = value
    }

    // ---- sensors (IDs verified with `kstatsviewer --list`) ----
    // A sensor is switched off when nothing shows its stat, so nothing polls for data nobody sees.
    Sensors.Sensor { id: cpuUsage;   sensorId: "cpu/all/usage";                updateRateLimit: root.refreshMs; enabled: root.showCpu || root.popupCpu }
    Sensors.Sensor { id: memPercent; sensorId: "memory/physical/usedPercent";  updateRateLimit: root.refreshMs; enabled: root.showRam || root.popupMemory }
    Sensors.Sensor { id: memUsed;    sensorId: "memory/physical/used";         updateRateLimit: root.refreshMs; enabled: root.popupMemory && root.expanded }
    Sensors.Sensor { id: memTotal;   sensorId: "memory/physical/total";        updateRateLimit: root.refreshMs; enabled: root.popupMemory && root.expanded }
    Sensors.Sensor { id: tempAvg;    sensorId: "cpu/all/averageTemperature";   updateRateLimit: root.refreshMs; enabled: root.showTemp || root.popupTempAvg }
    Sensors.Sensor { id: tempMax;    sensorId: "cpu/all/maximumTemperature";   updateRateLimit: root.refreshMs; enabled: root.popupTempMax && root.expanded }
    Sensors.Sensor { id: freqAvg;    sensorId: "cpu/all/averageFrequency";     updateRateLimit: root.refreshMs; enabled: root.showFreq || root.popupFreq }
    Sensors.Sensor { id: freqMin;    sensorId: "cpu/all/minimumFrequency";     updateRateLimit: root.refreshMs; enabled: root.popupFreq && root.expanded }
    Sensors.Sensor {
        id: freqMax
        sensorId: "cpu/all/maximumFrequency"
        updateRateLimit: root.refreshMs
        enabled: root.showFreq || root.popupFreq
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
        enabled: root.showNet || root.popupNet
        onValueChanged: root.trackNetPeak()          // once per refresh (upload updates in the same tick)
    }
    Sensors.Sensor { id: netUp; sensorId: "network/all/upload"; updateRateLimit: root.refreshMs; enabled: root.showNet || root.popupNet }
    Sensors.Sensor { id: netDownTotal; sensorId: "network/all/totalDownload"; updateRateLimit: root.refreshMs; enabled: root.popupNet && root.expanded }
    Sensors.Sensor { id: netUpTotal;   sensorId: "network/all/totalUpload";   updateRateLimit: root.refreshMs; enabled: root.popupNet && root.expanded }
    // Network graph scale: rises at once to the highest rate (down or up) and decays about 1% per
    // second of real time, whatever the refresh rate; never below 100 KB/s.
    property real netPeak: 100000
    function trackNetPeak() {
        if (!(gpNet || gdNet)) return                  // the scale only matters to a graph
        var d = isNum(netDown.value) ? Number(netDown.value) : 0
        var u = isNum(netUp.value) ? Number(netUp.value) : 0
        netPeak = Math.max(100000, d, u, netPeak * Math.pow(0.99, refreshMs / 1000))
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
        setCfg("batteryCount", hasBattery ? batterySources.length : 0)
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
        signal found(var ids, bool final)         // final: stop looking (found some, or gave up)
        property int attempts: 0
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
            if (ids.length > 0 || attempts >= maxAttempts) {
                found(ids, true)
            } else {
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
    // Graph scale: grows to the highest RPM seen, never below 3000.
    property real fanPeak: 3000
    onFanRpmChanged: if (isNum(fanRpm) && Number(fanRpm) > fanPeak) fanPeak = Number(fanRpm)
    QtObject { id: fanSensor; readonly property var value: root.fanRpm }

    // Number of per-core temperature sensors (cpu/cpuN/temperature, N = 0..count-1).
    Sensors.Sensor { id: coreCount;  sensorId: "cpu/all/coreCount"; enabled: root.popupCores && root.expanded }

    // ---- graph history ----
    // Each stat has its own history. It is collected only while a graph that
    // shows that stat is enabled, and it starts once the stat's sensor has
    // reported a real number (so the history never begins with fake zeros).
    readonly property int styleInline: 2   // stored value of "Inline"; keep in sync with configGraphs.qml (1 = behind text)
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
    History { id: netUpHistory;   sensor: netUp;   wanted: netDownHistory.wanted }
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

    // One small line graph; used by the panel cells and the popup.
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
    function pct(v)   { return isNum(v) ? Math.round(v) + "%" : "--%" }
    function tempNumber(v) { return isNum(v) ? String(Math.round(useF ? v * 9 / 5 + 32 : v)) : "--" }
    function temp(v) { return tempNumber(v) + (useF ? "°F" : "°C") }
    function gib(v)   { return isNum(v) ? (v / 1073741824).toFixed(1) + " GiB" : "-- GiB" }
    function rpmText(v) { return rpmNumber(v) + " RPM" }
    function wh(v) { return isNum(v) ? Number(v).toFixed(1) + " Wh" : "-- Wh" }
    function batText() { return batValue(batPercent, batState, false) }
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
    function statPopupGraph(id) {
        switch (id) {
        case "cpu":  return gdCpu
        case "ram":  return gdRam
        case "temp": return gdTemp
        case "freq": return gdFreq
        case "net":  return gdNet
        case "bat":  return gdBat
        case "fan":  return gdFan
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
    FontMetrics { id: fm; font: Kirigami.Theme.defaultFont }                        // width of any string
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

    // Widest line of a stat's text on a vertical panel (what must fit in the panel's thickness): the
    // worst-case lines of verticalLines, so the width and the text come from the same code.
    function verticalWidth(id) {
        void fm.font                         // re-measure when the font changes (advanceWidth is not bindable)
        var lines = verticalLines(id, false, true), w = 0
        for (var i = 0; i < lines.length; ++i) w = Math.max(w, fm.advanceWidth(lines[i]))
        if (id === "fan") w = Math.max(w, Kirigami.Units.iconSizes.smallMedium)
        return Math.ceil(w)
    }
    // The panel's thickness (set by the vertical compact view); 0 until known or when horizontal.
    property real panelThickness: 0
    // Whether a stat's value text is shortened. Horizontal: the length step. Vertical: only this stat's own
    // full text being wider than the panel (shortening saves no length there, so it is not a length step).
    function statCompact(id) {
        if (!vertical) return lengthLevel >= 2
        // Only these three have a shorter form; measuring the rest could never change their text.
        if (id !== "temp" && id !== "freq" && id !== "bat") return false
        return panelThickness > 0 && verticalWidth(id) > panelThickness - Kirigami.Units.smallSpacing * 2
    }

    function tempShort(v) { return tempNumber(v) + "°" }
    function freqShort(v) {
        if (!isNum(v)) return "--G"
        return v >= 1000 ? (v / 1000).toFixed(1) + "G" : Math.round(v) + "M"
    }
    function arrowFor(state) { return state > 0 ? "↑" : (state < 0 ? "↓" : "") }
    function batValue(percent, state, compact) {
        var a = arrowFor(state)
        return pct(percent) + (compact ? a : (a ? " " + a : ""))
    }
    function rpmNumber(v) { return isNum(v) ? String(Math.round(Number(v))) : "--" }

    // Per-stat colours, history and graph scale, so a panel cell needs nothing but its id.
    function statAlert(id) { return (id === "temp" && avgHot) || (id === "bat" && batLow) }
    function statTextColor(id) { return statAlert(id) ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor }
    function statLineColor(id) { return statAlert(id) ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor }
    function statHistory(id) {
        switch (id) {
        case "cpu":  return cpuHist
        case "ram":  return ramHist
        case "temp": return tempHist
        case "freq": return freqHist
        case "net":  return netDownHist
        case "bat":  return batHist
        case "fan":  return fanHist
        }
        return null
    }
    function statHistory2(id) { return id === "net" ? netUpHist : null }
    function statYFrom(id) { return id === "temp" ? tempYMin : 0 }
    function statYTo(id) {
        switch (id) {
        case "temp": return tempYMax
        case "freq": return freqPeak
        case "net":  return netPeak
        case "fan":  return fanPeak
        }
        return 100
    }

    // The value of a stat and a worst-case sample of it (the widest it can get, for width calculations).
    function statValue(id, sample) {
        switch (id) {
        case "cpu":  return sample ? 100 : cpuUsage.value
        case "ram":  return sample ? 100 : memPercent.value
        case "temp": return sample ? 100 : tempAvg.value
        case "freq": return sample ? 9900 : freqAvg.value      // 9.9 GHz, as the horizontal reserve
        case "bat":  return sample ? 100 : batPercent
        case "fan":  return sample ? 9999 : fanRpm
        }
        return 0
    }
    // The value part of a stat's text (no caption), shared by the horizontal and the vertical panel.
    function valueText(id, compact, sample) {
        var v = statValue(id, sample)
        switch (id) {
        case "cpu":
        case "ram":  return pct(v)
        case "temp": return compact ? tempShort(v) : temp(v)
        case "freq": return compact ? freqShort(v) : freq(v)
        case "bat":  return batValue(v, sample ? 1 : batState, compact)
        case "fan":  return rpmNumber(v)
        }
        return ""
    }
    // Net has two values; in bits mode the sample is scaled so it is the widest in either unit.
    function netLines(sample) {
        var d = sample ? (netBits ? 999e6 / 8 : 999e6) : netDown.value
        var u = sample ? d : netUp.value
        return ["↓" + rateShort(d), "↑" + rateShort(u)]
    }
    // The text of a stat in the panel, for the current step (compact or full) and orientation.
    // On a vertical panel the caption line is always kept, so it is easy to tell which stat is shown;
    // only the value line is shortened.
    function statText(id, compact, vert) {
        if (vert) return verticalLines(id, compact, false).join("\n")
        var v = valueText(id, compact, false)
        switch (id) {
        case "cpu":  return (compact ? "C " : "CPU ") + v
        case "ram":  return (compact ? "R " : "RAM ") + v
        case "temp":
        case "freq": return v
        case "net":  { var n = netLines(false); return compact ? n[0] + " " + n[1] : netText() }
        case "bat":  return (compact ? "B " : "BAT ") + v
        case "fan":  return compact ? v : rpmText(fanRpm)
        }
        return ""
    }
    function verticalCaption(id) {
        switch (id) {
        case "cpu":  return "CPU"
        case "ram":  return "RAM"
        case "temp": return "Temp"
        case "freq": return "Freq"
        case "net":  return "Net"
        case "bat":  return "Bat"
        case "fan":  return "Fan"
        }
        return ""
    }
    // The lines of a stat on a vertical panel: caption, then the value line(s). `sample` gives the widest
    // possible values instead of the live ones.
    function verticalLines(id, compact, sample) {
        var cap = verticalCaption(id)
        return id === "net" ? [cap].concat(netLines(sample)) : [cap, valueText(id, compact, sample)]
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
            if (id === "fan") w += Kirigami.Units.iconSizes.smallMedium + gap
            if (inlineGraph) w += gap + inlineGraphWidth
            return w
        }
        var h = verticalLines(id, false, true).length * mLine.height    // caption + value line(s)
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
    property real dragLength: 0              // strip length under the mouse, px
    // Which edge carries the handle: the edge that is free to move. A widget in the far half of the
    // panel (right half, or bottom half when vertical) is packed toward the end, so the strip grows
    // toward the start and the handle sits on the left (top) edge. Otherwise it sits on the right (bottom).
    property bool handleAtStart: false
    // Strip length for a pointer at `pos`, given where the drag started. With the handle on the
    // start edge, moving the pointer toward the start makes the strip longer, so the sign flips.
    function dragTo(startLength, startPos, pos) {
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
        spacing: Kirigami.Units.largeSpacing
        PlasmaComponents.Label { text: popupRow.name; Layout.preferredWidth: root.popupLabelWidth }
        PlasmaComponents.Label { text: popupRow.value; font.bold: true; color: popupRow.valueColor }
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

    function popupBlock(id) {
        switch (id) {
        case "cpu":  return cpuBlock
        case "ram":  return ramBlock
        case "temp": return tempBlock
        case "freq": return freqBlock
        case "net":  return netBlock
        case "bat":  return batBlock
        case "fan":  return fanBlock
        }
        return null
    }

    Component {
        id: cpuBlock
        ColumnLayout {
            PopupRow { name: "CPU usage"; value: root.pct(cpuUsage.value) }
            PopupGraph { statId: "cpu" }
        }
    }
    Component {
        id: ramBlock
        ColumnLayout {
            PopupRow {
                name: "Memory"
                value: root.gib(memUsed.value) + " / " + root.gib(memTotal.value) + " (" + root.pct(memPercent.value) + ")"
            }
            PopupGraph { statId: "ram" }
        }
    }
    Component {
        id: freqBlock
        ColumnLayout {
            PopupRow { name: "CPU frequency"; value: root.freq(freqAvg.value) }
            PopupRow { name: "Min / max"; value: root.ghzNumber(freqMin.value) + " / " + root.ghzNumber(freqMax.value) + " GHz" }
            PopupGraph { statId: "freq" }
        }
    }
    Component {
        id: netBlock
        ColumnLayout {
            PopupRow { name: "Download"; value: root.rate(netDown.value) + "  (" + root.bytesText(netDownTotal.value) + " total)" }
            PopupRow { name: "Upload"; value: root.rate(netUp.value) + "  (" + root.bytesText(netUpTotal.value) + " total)" }
            PopupGraph { statId: "net" }
        }
    }
    Component {
        id: batBlock
        ColumnLayout {
            PopupRow {
                name: "Battery"
                value: root.batText() + (root.isNum(root.batEnergyTotal()) ? "  (" + root.wh(root.batEnergyTotal()) + ")" : "")
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
    Component {
        id: fanBlock
        ColumnLayout {
            RowLayout {
                spacing: Kirigami.Units.largeSpacing
                PlasmaComponents.Label { text: "Fan"; Layout.preferredWidth: root.popupLabelWidth }
                RowLayout {
                    spacing: Kirigami.Units.smallSpacing
                    FanIcon {
                        level: root.fanLevel
                        animate: root.fanAnimate
                    }
                    PlasmaComponents.Label { text: root.rpmText(root.fanRpm); font.bold: true }
                }
            }
            PopupGraph { statId: "fan" }
        }
    }
    Component {
        id: tempBlock
        ColumnLayout {
            PopupRow {
                visible: root.popupTempAvg
                name: "CPU temp (avg)"
                value: root.temp(tempAvg.value)
                valueColor: root.statTextColor("temp")
            }
            PopupGraph { statId: "temp"; wanted: root.popupTempAvg }
            PopupRow {
                visible: root.popupTempMax
                name: "CPU temp (max core)"
                value: root.temp(tempMax.value)
                valueColor: root.tempHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
            }

            // ---- per-core temperatures ----
            // Sensors are created per delegate, so they only exist while the popup is open.
            // Threads of one physical core (hyperthreading) report the same temperature.
            PlasmaComponents.Label {
                visible: root.popupCores && perCore.count > 0
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: "Per core"
                font.bold: true
            }
            GridLayout {
                visible: root.popupCores && perCore.count > 0
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
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14

        Repeater {
            model: root.statOrder
            delegate: Loader {
                required property string modelData
                Layout.fillWidth: true
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
