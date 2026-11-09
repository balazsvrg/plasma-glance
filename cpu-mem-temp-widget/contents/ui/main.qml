import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors

PlasmoidItem {
    id: root

    readonly property int refreshMs: 2000
    readonly property real warnTempC: 80

    // ---- sensors (IDs verified with `kstatsviewer --list`) ----
    Sensors.Sensor { id: cpuUsage;   sensorId: "cpu/all/usage";                updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memPercent; sensorId: "memory/physical/usedPercent";  updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memUsed;    sensorId: "memory/physical/used";         updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: memTotal;   sensorId: "memory/physical/total";        updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: tempAvg;    sensorId: "cpu/all/averageTemperature";   updateRateLimit: root.refreshMs }
    Sensors.Sensor { id: tempMax;    sensorId: "cpu/all/maximumTemperature";   updateRateLimit: root.refreshMs }

    // ---- formatting helpers ----
    function isNum(v) { return v !== undefined && v !== null && !isNaN(v) }
    function pct(v)   { return isNum(v) ? Math.round(v) + "%" : "--%" }
    function temp(v)  { return isNum(v) ? Math.round(v) + "°C" : "--°C" }
    function gib(v)   { return isNum(v) ? (v / 1073741824).toFixed(1) + " GiB" : "-- GiB" }

    readonly property bool tempHot: isNum(tempMax.value) && tempMax.value >= warnTempC

    preferredRepresentation: compactRepresentation
    toolTipMainText: "System stats"
    toolTipSubText: "CPU " + pct(cpuUsage.value) + " · RAM " + pct(memPercent.value)
                    + " · " + temp(tempAvg.value)

    compactRepresentation: MouseArea {
        id: compact
        onClicked: root.expanded = !root.expanded

        readonly property bool vertical: Plasmoid.formFactor === 3 // PlasmaCore.Types.Vertical

        Layout.minimumWidth: layout.implicitWidth
        Layout.minimumHeight: layout.implicitHeight

        GridLayout {
            id: layout
            anchors.centerIn: parent
            columns: compact.vertical ? 1 : 3
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: 0

            PlasmaComponents.Label {
                text: "CPU " + root.pct(cpuUsage.value)
            }
            PlasmaComponents.Label {
                text: "RAM " + root.pct(memPercent.value)
            }
            PlasmaComponents.Label {
                text: root.temp(tempAvg.value)
                color: root.tempHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
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
        PlasmaComponents.Label { text: root.temp(tempAvg.value); font.bold: true }

        PlasmaComponents.Label { text: "CPU temp (max core)" }
        PlasmaComponents.Label {
            text: root.temp(tempMax.value)
            font.bold: true
            color: root.tempHot ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }
    }
}
