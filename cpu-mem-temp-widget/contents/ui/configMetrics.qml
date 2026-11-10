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
    }
}
