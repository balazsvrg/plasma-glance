import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// One row per stat: whether it shows in the panel strip and in the click-open popup.
KCM.SimpleKCM {
    id: page

    // Bound by Plasma to the entries in contents/config/main.xml.
    property alias cfg_showCpu: cpuPanel.checked
    property alias cfg_popupCpu: cpuPopup.checked
    property alias cfg_showRam: ramPanel.checked
    property alias cfg_popupMemory: ramPopup.checked
    property alias cfg_showTemp: tempPanel.checked
    property alias cfg_popupTempAvg: tempPopup.checked
    property alias cfg_popupTempMax: tempMaxPopup.checked
    property alias cfg_popupCores: coresPopup.checked
    property alias cfg_showFreq: freqPanel.checked
    property alias cfg_popupFreq: freqPopup.checked
    property alias cfg_showNet: netPanel.checked
    property alias cfg_popupNet: netPopup.checked
    property alias cfg_showBat: batPanel.checked
    property alias cfg_popupBat: batPopup.checked
    property int cfg_batteryCount           // written by the widget when it detects batteries
    property alias cfg_showFan: fanPanel.checked
    property alias cfg_popupFan: fanPopup.checked
    property alias cfg_fanAnimate: fanAnimate.checked
    property int cfg_fanCount               // written by the widget when it detects fans
    property bool cfg_batSeparate

    property bool cfg_showCpuDefault
    property bool cfg_popupCpuDefault
    property bool cfg_showRamDefault
    property bool cfg_popupMemoryDefault
    property bool cfg_showTempDefault
    property bool cfg_popupTempAvgDefault
    property bool cfg_popupTempMaxDefault
    property bool cfg_popupCoresDefault
    property bool cfg_showFreqDefault
    property bool cfg_popupFreqDefault
    property bool cfg_showNetDefault
    property bool cfg_popupNetDefault
    property bool cfg_showBatDefault
    property bool cfg_popupBatDefault
    property int cfg_batteryCountDefault
    property bool cfg_batSeparateDefault
    property bool cfg_showFanDefault
    property bool cfg_popupFanDefault
    property bool cfg_fanAnimateDefault
    property int cfg_fanCountDefault

    GridLayout {
        columns: 3
        columnSpacing: Kirigami.Units.gridUnit * 2
        rowSpacing: Kirigami.Units.smallSpacing

        QQC2.Label { text: i18n("Stat"); font.bold: true }
        QQC2.Label { text: i18n("Panel"); font.bold: true; Layout.alignment: Qt.AlignHCenter }
        QQC2.Label { text: i18n("Popup"); font.bold: true; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("CPU usage") }
        QQC2.CheckBox { id: cpuPanel; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: cpuPopup; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("Memory") }
        QQC2.CheckBox { id: ramPanel; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: ramPopup; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("CPU temperature") }
        QQC2.CheckBox { id: tempPanel; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: tempPopup; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("Hottest core"); Layout.leftMargin: Kirigami.Units.gridUnit; opacity: 0.8 }
        Item { }
        QQC2.CheckBox { id: tempMaxPopup; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("Per-core temperatures"); Layout.leftMargin: Kirigami.Units.gridUnit; opacity: 0.8 }
        Item { }
        QQC2.CheckBox { id: coresPopup; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("CPU frequency") }
        QQC2.CheckBox { id: freqPanel; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: freqPopup; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("Network speed") }
        QQC2.CheckBox { id: netPanel; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: netPopup; Layout.alignment: Qt.AlignHCenter }

        // Only shown on machines where the widget found a battery.
        QQC2.Label { text: i18n("Battery"); visible: page.cfg_batteryCount > 0 }
        QQC2.CheckBox { id: batPanel; visible: page.cfg_batteryCount > 0; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: batPopup; visible: page.cfg_batteryCount > 0; Layout.alignment: Qt.AlignHCenter }

        // Only shown on machines where the widget found a fan sensor.
        QQC2.Label { text: i18n("Fan speed"); visible: page.cfg_fanCount > 0 }
        QQC2.CheckBox { id: fanPanel; visible: page.cfg_fanCount > 0; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: fanPopup; visible: page.cfg_fanCount > 0; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox {
            id: fanAnimate
            visible: page.cfg_fanCount > 0
            Layout.columnSpan: 3
            Layout.leftMargin: Kirigami.Units.gridUnit
            text: i18n("Animate fan icon based on fan speed")
        }

        // Only offered when there are several batteries to separate.
        QQC2.Label {
            visible: page.cfg_batteryCount > 1
            text: i18n("Popup battery view")
            Layout.topMargin: Kirigami.Units.largeSpacing
        }
        QQC2.ComboBox {
            id: batViewBox
            visible: page.cfg_batteryCount > 1
            Layout.columnSpan: 2
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
            model: [i18n("Combined"), i18n("Each battery separately")]
            onActivated: page.cfg_batSeparate = (currentIndex === 1)
        }
        Binding {
            target: batViewBox
            property: "currentIndex"
            value: page.cfg_batSeparate ? 1 : 0
        }
    }
}
