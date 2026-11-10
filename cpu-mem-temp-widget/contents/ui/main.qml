import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.quickcharts as Charts

PlasmoidItem {
    id: root

    // ---- user settings (contents/config/main.xml) ----
    readonly property int refreshMs: Math.max(250, Plasmoid.configuration.refreshMs)
    readonly property real warnTempC: Plasmoid.configuration.warnTemp
    readonly property bool showCpu: Plasmoid.configuration.showCpu
    readonly property bool showRam: Plasmoid.configuration.showRam
    readonly property bool showTemp: Plasmoid.configuration.showTemp
    readonly property bool showFreq: Plasmoid.configuration.showFreq
    readonly property bool useF: Plasmoid.configuration.useFahrenheit
    readonly property bool popupCpu: Plasmoid.configuration.popupCpu
    readonly property bool popupMemory: Plasmoid.configuration.popupMemory
    readonly property bool popupTempAvg: Plasmoid.configuration.popupTempAvg
    readonly property bool popupTempMax: Plasmoid.configuration.popupTempMax
    readonly property bool popupCores: Plasmoid.configuration.popupCores
    readonly property bool popupFreq: Plasmoid.configuration.popupFreq

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

    readonly property var cpuHist:  cpuHistory.historySource
    readonly property var ramHist:  ramHistory.historySource
    readonly property var tempHist: tempHistory.historySource
    readonly property var freqHist: freqHistory.historySource

    // One small line graph; used by the popup and (next) the panel.
    component Spark: Charts.LineChart {
        id: spark
        property var history: null
        property real yFrom: 0
        property real yTo: 100
        property color lineColor: Kirigami.Theme.highlightColor

        valueSources: history ? [history] : []
        colorSource: Charts.SingleValueSource { value: spark.lineColor }
        xRange { automatic: true }            // spans the samples collected so far
        yRange { from: spark.yFrom; to: spark.yTo; automatic: false }
        direction: Charts.XYChart.ZeroAtEnd   // newest sample on the right
        lineWidth: 1.5
        fillOpacity: 0.15
        interpolate: false
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
            property real minLabelWidth: 0
            property color textColor: Kirigami.Theme.textColor
            property var history: null
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
                yFrom: cell.yFrom
                yTo: cell.yTo
                lineColor: cell.lineColor
            }

            GridLayout {
                id: content
                anchors.fill: parent
                columns: compact.vertical ? 1 : 2
                columnSpacing: Kirigami.Units.smallSpacing
                rowSpacing: 0

                PlasmaComponents.Label {
                    Layout.alignment: Qt.AlignCenter
                    Layout.minimumWidth: compact.vertical ? 0 : cell.minLabelWidth
                    Layout.preferredWidth: compact.vertical ? -1 : cell.minLabelWidth
                    Layout.fillWidth: compact.vertical
                    horizontalAlignment: Text.AlignHCenter
                    fontSizeMode: compact.vertical ? Text.HorizontalFit : Text.FixedSize
                    minimumPixelSize: 8
                    text: compact.vertical ? cell.caption + "\n" + cell.valueText
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
                    yFrom: cell.yFrom
                    yTo: cell.yTo
                    lineColor: cell.lineColor
                }
            }
        }

        GridLayout {
            id: layout
            anchors.fill: parent
            columns: compact.vertical ? 1 : 7
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
            PlasmaComponents.Label {
                visible: !root.showCpu && !root.showRam && !root.showTemp && !root.showFreq
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
                     && !root.popupTempMax && !root.popupCores && !root.popupFreq
            Layout.columnSpan: 2
            text: "Nothing to show. Enable items under Configure > Metrics."
            opacity: 0.7
        }
    }
}
