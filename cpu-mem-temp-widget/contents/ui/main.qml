import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root

    // ---- user settings (contents/config/main.xml) ----
    readonly property int refreshMs: Math.max(250, Plasmoid.configuration.refreshMs)
    readonly property real warnTempC: Plasmoid.configuration.warnTemp
    readonly property bool showCpu: Plasmoid.configuration.showCpu
    readonly property bool showRam: Plasmoid.configuration.showRam
    readonly property bool showTemp: Plasmoid.configuration.showTemp
    readonly property bool useF: Plasmoid.configuration.useFahrenheit

    // ---- sensors (IDs verified with `kstatsviewer --list`) ----
    Sensors.Sensor { id: cpuUsage;   sensorId: "cpu/all/usage";                updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memPercent; sensorId: "memory/physical/usedPercent";  updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memUsed;    sensorId: "memory/physical/used";         updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memTotal;   sensorId: "memory/physical/total";        updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: tempAvg;    sensorId: "cpu/all/averageTemperature";   updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: tempMax;    sensorId: "cpu/all/maximumTemperature";   updateRateLimit: root.refreshMs }

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

        GridLayout {
            id: layout
            anchors.fill: parent
            columns: compact.vertical ? 1 : 5
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing

            PlasmaComponents.Label {
                visible: root.showCpu
                Layout.alignment: Qt.AlignCenter
                Layout.minimumWidth: compact.vertical ? 0 : cpuMetrics.width
                Layout.fillWidth: compact.vertical
                horizontalAlignment: Text.AlignHCenter
                fontSizeMode: compact.vertical ? Text.HorizontalFit : Text.FixedSize
                minimumPixelSize: 8
                text: compact.vertical ? "CPU\n" + root.pct(cpuUsage.value) : "CPU " + root.pct(cpuUsage.value)
            }
            Divider { visible: root.showCpu && (root.showRam || root.showTemp) }
            PlasmaComponents.Label {
                visible: root.showRam
                Layout.alignment: Qt.AlignCenter
                Layout.minimumWidth: compact.vertical ? 0 : ramMetrics.width
                Layout.fillWidth: compact.vertical
                horizontalAlignment: Text.AlignHCenter
                fontSizeMode: compact.vertical ? Text.HorizontalFit : Text.FixedSize
                minimumPixelSize: 8
                text: compact.vertical ? "RAM\n" + root.pct(memPercent.value) : "RAM " + root.pct(memPercent.value)
            }
            Divider { visible: root.showRam && root.showTemp }
            PlasmaComponents.Label {
                visible: root.showTemp
                Layout.alignment: Qt.AlignCenter
                Layout.minimumWidth: compact.vertical ? 0 : tempMetrics.width
                Layout.fillWidth: compact.vertical
                horizontalAlignment: Text.AlignHCenter
                fontSizeMode: compact.vertical ? Text.HorizontalFit : Text.FixedSize
                minimumPixelSize: 8
                text: compact.vertical ? "Temp\n" + root.temp(tempAvg.value) : root.temp(tempAvg.value)
                color: root.avgHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
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

        PlasmaComponents.Label { text: "CPU usage" }
        PlasmaComponents.Label { text: root.pct(cpuUsage.value); font.bold: true }

        PlasmaComponents.Label { text: "Memory" }
        PlasmaComponents.Label {
            text: root.gib(memUsed.value) + " / " + root.gib(memTotal.value)
                  + " (" + root.pct(memPercent.value) + ")"
            font.bold: true
        }

        PlasmaComponents.Label { text: "CPU temp (avg)" }
        PlasmaComponents.Label {
            text: root.temp(tempAvg.value)
            font.bold: true
            color: root.avgHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }

        PlasmaComponents.Label { text: "CPU temp (max core)" }
        PlasmaComponents.Label {
            text: root.temp(tempMax.value)
            font.bold: true
            color: root.tempHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }
    }
}
