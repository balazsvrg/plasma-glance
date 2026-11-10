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
    readonly property bool useF: Plasmoid.configuration.useFahrenheit
    readonly property bool popupCpu: Plasmoid.configuration.popupCpu
    readonly property bool popupMemory: Plasmoid.configuration.popupMemory
    readonly property bool popupTempAvg: Plasmoid.configuration.popupTempAvg
    readonly property bool popupTempMax: Plasmoid.configuration.popupTempMax
    readonly property bool popupCores: Plasmoid.configuration.popupCores

    // ---- sensors (IDs verified with `kstatsviewer --list`) ----
    Sensors.Sensor { id: cpuUsage;   sensorId: "cpu/all/usage";                updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memPercent; sensorId: "memory/physical/usedPercent";  updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memUsed;    sensorId: "memory/physical/used";         updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memTotal;   sensorId: "memory/physical/total";        updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: tempAvg;    sensorId: "cpu/all/averageTemperature";   updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: tempMax;    sensorId: "cpu/all/maximumTemperature";   updateRateLimit: root.refreshMs }
    // Number of per-core temperature sensors (cpu/cpuN/temperature, N = 0..count-1).
    Sensors.Sensor { id: coreCount;  sensorId: "cpu/all/coreCount" }

    // ---- graph history ----
    // Samples are collected only while some graph is enabled (the Loader is
    // inactive otherwise), so there is no background cost when graphs are off.
    readonly property int panelGraphStyle: Plasmoid.configuration.panelGraphStyle // 0 off, 1 behind, 2 inline
    readonly property bool popupGraphs: Plasmoid.configuration.popupGraphs
    readonly property bool graphsActive: panelGraphStyle > 0 || popupGraphs
    // Start recording only once all three sensors report real values, so the
    // history does not begin with fake zeros.
    readonly property bool sensorsReady: isNum(cpuUsage.value) && isNum(memPercent.value) && isNum(tempAvg.value)
    readonly property int historyLen: Math.max(10, Math.round(Plasmoid.configuration.historySeconds * 1000 / refreshMs))
    readonly property var cpuHist:  histories.item ? histories.item.cpu  : null
    readonly property var ramHist:  histories.item ? histories.item.ram  : null
    readonly property var tempHist: histories.item ? histories.item.temp : null

    Loader {
        id: histories
        active: root.graphsActive && root.sensorsReady
        sourceComponent: Item {
            property alias cpu: cpuH
            property alias ram: ramH
            property alias temp: tempH

            Charts.HistoryProxySource {
                id: cpuH
                source: Charts.SingleValueSource { value: cpuUsage.value }
                maximumHistory: root.historyLen
                interval: root.refreshMs
                fillMode: Charts.HistoryProxySource.DoNotFill
            }
            Charts.HistoryProxySource {
                id: ramH
                source: Charts.SingleValueSource { value: memPercent.value }
                maximumHistory: root.historyLen
                interval: root.refreshMs
                fillMode: Charts.HistoryProxySource.DoNotFill
            }
            Charts.HistoryProxySource {
                id: tempH
                source: Charts.SingleValueSource { value: tempAvg.value }
                maximumHistory: root.historyLen
                interval: root.refreshMs
                fillMode: Charts.HistoryProxySource.DoNotFill
            }
        }
    }

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

    // Each temperature is highlighted by its own value, so the colour always
    // matches the number shown next to it.
    readonly property bool avgHot: isNum(tempAvg.value) && tempAvg.value >= warnTempC
    readonly property bool tempHot: isNum(tempMax.value) && tempMax.value >= warnTempC

    function tooltipText() {
        var parts = []
        if (showCpu)  parts.push("CPU " + pct(cpuUsage.value))
        if (showRam)  parts.push("RAM " + pct(memPercent.value))
        if (showTemp) parts.push(temp(tempAvg.value))
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

            readonly property bool hasGraph: root.panelGraphStyle > 0 && history !== null
            readonly property bool behind: hasGraph && root.panelGraphStyle === 1
            readonly property bool inline: hasGraph && root.panelGraphStyle === 2

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight

            Spark {
                visible: cell.behind
                anchors.fill: parent
                opacity: 0.5
                history: cell.history
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
                    history: cell.history
                    yFrom: cell.yFrom
                    yTo: cell.yTo
                    lineColor: cell.lineColor
                }
            }
        }

        GridLayout {
            id: layout
            anchors.fill: parent
            columns: compact.vertical ? 1 : 5
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
            Divider { visible: root.showCpu && (root.showRam || root.showTemp) }
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
            Divider { visible: root.showRam && root.showTemp }
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
                yFrom: 20
                yTo: 100
                lineColor: root.avgHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.highlightColor
            }
            PlasmaComponents.Label {
                visible: !root.showCpu && !root.showRam && !root.showTemp
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
            history: root.cpuHist
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
            history: root.ramHist
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
            history: root.tempHist
            yFrom: 20
            yTo: 100
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
                     && !root.popupTempMax && !root.popupCores
            Layout.columnSpan: 2
            text: "Nothing to show. Enable items under Configure > Popup."
            opacity: 0.7
        }
    }
}
