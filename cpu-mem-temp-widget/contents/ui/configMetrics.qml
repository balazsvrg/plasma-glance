import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

// One row per stat: shown in the panel strip and/or the click-open popup, and whether
// each of those places gets a graph.
KCM.SimpleKCM {
    id: page

    // Bound by Plasma to the entries in contents/config/main.xml.
    property alias cfg_showCpu: cpuPanel.checked
    property alias cfg_graphPanelCpu: cpuPanelGraph.checked
    property alias cfg_popupCpu: cpuPopup.checked
    property alias cfg_graphPopupCpu: cpuPopupGraph.checked

    property alias cfg_showRam: ramPanel.checked
    property alias cfg_graphPanelRam: ramPanelGraph.checked
    property alias cfg_popupMemory: ramPopup.checked
    property alias cfg_graphPopupRam: ramPopupGraph.checked

    property alias cfg_showTemp: tempPanel.checked
    property alias cfg_graphPanelTemp: tempPanelGraph.checked
    property alias cfg_popupTempAvg: tempPopup.checked
    property alias cfg_graphPopupTemp: tempPopupGraph.checked
    property alias cfg_popupTempMax: tempMaxPopup.checked
    property alias cfg_popupCores: coresPopup.checked

    property alias cfg_showFreq: freqPanel.checked
    property alias cfg_graphPanelFreq: freqPanelGraph.checked
    property alias cfg_popupFreq: freqPopup.checked
    property alias cfg_graphPopupFreq: freqPopupGraph.checked

    property alias cfg_showNet: netPanel.checked
    property alias cfg_graphPanelNet: netPanelGraph.checked
    property alias cfg_popupNet: netPopup.checked
    property alias cfg_graphPopupNet: netPopupGraph.checked

    property alias cfg_showBat: batPanel.checked
    property alias cfg_graphPanelBat: batPanelGraph.checked
    property alias cfg_popupBat: batPopup.checked
    property alias cfg_graphPopupBat: batPopupGraph.checked
    property int cfg_batteryCount           // written by the widget when it detects batteries
    property bool cfg_batSeparate

    property alias cfg_showFan: fanPanel.checked
    property alias cfg_graphPanelFan: fanPanelGraph.checked
    property alias cfg_popupFan: fanPopup.checked
    property alias cfg_graphPopupFan: fanPopupGraph.checked
    property alias cfg_fanAnimate: fanAnimate.checked
    property int cfg_fanCount               // written by the widget when it detects fans

    property bool cfg_showCpuDefault
    property bool cfg_graphPanelCpuDefault
    property bool cfg_popupCpuDefault
    property bool cfg_graphPopupCpuDefault
    property bool cfg_showRamDefault
    property bool cfg_graphPanelRamDefault
    property bool cfg_popupMemoryDefault
    property bool cfg_graphPopupRamDefault
    property bool cfg_showTempDefault
    property bool cfg_graphPanelTempDefault
    property bool cfg_popupTempAvgDefault
    property bool cfg_graphPopupTempDefault
    property bool cfg_popupTempMaxDefault
    property bool cfg_popupCoresDefault
    property bool cfg_showFreqDefault
    property bool cfg_graphPanelFreqDefault
    property bool cfg_popupFreqDefault
    property bool cfg_graphPopupFreqDefault
    property bool cfg_showNetDefault
    property bool cfg_graphPanelNetDefault
    property bool cfg_popupNetDefault
    property bool cfg_graphPopupNetDefault
    property bool cfg_showBatDefault
    property bool cfg_graphPanelBatDefault
    property bool cfg_popupBatDefault
    property bool cfg_graphPopupBatDefault
    property int cfg_batteryCountDefault
    property bool cfg_batSeparateDefault
    property bool cfg_showFanDefault
    property bool cfg_graphPanelFanDefault
    property bool cfg_popupFanDefault
    property bool cfg_graphPopupFanDefault
    property bool cfg_fanAnimateDefault
    property int cfg_fanCountDefault

    // "All graphs" row: checked when every graph box that is shown is checked.
    readonly property bool hasBat: cfg_batteryCount > 0
    readonly property bool hasFan: cfg_fanCount > 0
    readonly property bool allPanelGraphs: cpuPanelGraph.checked && ramPanelGraph.checked
        && tempPanelGraph.checked && freqPanelGraph.checked && netPanelGraph.checked
        && (!hasBat || batPanelGraph.checked) && (!hasFan || fanPanelGraph.checked)
    readonly property bool allPopupGraphs: cpuPopupGraph.checked && ramPopupGraph.checked
        && tempPopupGraph.checked && freqPopupGraph.checked && netPopupGraph.checked
        && (!hasBat || batPopupGraph.checked) && (!hasFan || fanPopupGraph.checked)
    function setAllPanelGraphs(on) {
        cpuPanelGraph.checked = ramPanelGraph.checked = tempPanelGraph.checked
            = freqPanelGraph.checked = netPanelGraph.checked = batPanelGraph.checked
            = fanPanelGraph.checked = on
    }
    function setAllPopupGraphs(on) {
        cpuPopupGraph.checked = ramPopupGraph.checked = tempPopupGraph.checked
            = freqPopupGraph.checked = netPopupGraph.checked = batPopupGraph.checked
            = fanPopupGraph.checked = on
    }

    GridLayout {
        columns: 5
        columnSpacing: Kirigami.Units.gridUnit * 1.5
        rowSpacing: Kirigami.Units.smallSpacing

        // Group headers
        Item { }
        QQC2.Label { text: i18n("In the panel"); font.bold: true; Layout.columnSpan: 2; Layout.alignment: Qt.AlignHCenter }
        QQC2.Label { text: i18n("In the popup"); font.bold: true; Layout.columnSpan: 2; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("Stat"); font.bold: true }
        QQC2.Label { text: i18n("Show"); opacity: 0.8; Layout.alignment: Qt.AlignHCenter }
        QQC2.Label { text: i18n("Graph"); opacity: 0.8; Layout.alignment: Qt.AlignHCenter }
        QQC2.Label { text: i18n("Show"); opacity: 0.8; Layout.alignment: Qt.AlignHCenter }
        QQC2.Label { text: i18n("Graph"); opacity: 0.8; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("CPU usage") }
        QQC2.CheckBox { id: cpuPanel; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: cpuPanelGraph; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: cpuPopup; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: cpuPopupGraph; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("Memory") }
        QQC2.CheckBox { id: ramPanel; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: ramPanelGraph; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: ramPopup; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: ramPopupGraph; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("CPU temperature") }
        QQC2.CheckBox { id: tempPanel; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: tempPanelGraph; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: tempPopup; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: tempPopupGraph; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("Hottest core"); Layout.leftMargin: Kirigami.Units.gridUnit; opacity: 0.8 }
        Item { }
        Item { }
        QQC2.CheckBox { id: tempMaxPopup; Layout.alignment: Qt.AlignHCenter }
        Item { }

        QQC2.Label { text: i18n("Per-core temperatures"); Layout.leftMargin: Kirigami.Units.gridUnit; opacity: 0.8 }
        Item { }
        Item { }
        QQC2.CheckBox { id: coresPopup; Layout.alignment: Qt.AlignHCenter }
        Item { }

        QQC2.Label { text: i18n("CPU frequency") }
        QQC2.CheckBox { id: freqPanel; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: freqPanelGraph; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: freqPopup; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: freqPopupGraph; Layout.alignment: Qt.AlignHCenter }

        QQC2.Label { text: i18n("Network speed") }
        QQC2.CheckBox { id: netPanel; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: netPanelGraph; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: netPopup; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: netPopupGraph; Layout.alignment: Qt.AlignHCenter }

        // Only shown on machines where the widget found a battery.
        QQC2.Label { text: i18n("Battery"); visible: page.hasBat }
        QQC2.CheckBox { id: batPanel; visible: page.hasBat; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: batPanelGraph; visible: page.hasBat; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: batPopup; visible: page.hasBat; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: batPopupGraph; visible: page.hasBat; Layout.alignment: Qt.AlignHCenter }

        // Only shown on machines where the widget found a fan sensor.
        QQC2.Label { text: i18n("Fan speed"); visible: page.hasFan }
        QQC2.CheckBox { id: fanPanel; visible: page.hasFan; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: fanPanelGraph; visible: page.hasFan; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: fanPopup; visible: page.hasFan; Layout.alignment: Qt.AlignHCenter }
        QQC2.CheckBox { id: fanPopupGraph; visible: page.hasFan; Layout.alignment: Qt.AlignHCenter }

        // Turn every graph on or off at once.
        QQC2.Label { text: i18n("All graphs"); font.bold: true; Layout.topMargin: Kirigami.Units.largeSpacing }
        Item { }
        QQC2.CheckBox {
            id: allPanelBox
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.largeSpacing
            onToggled: page.setAllPanelGraphs(checked)
        }
        Item { }
        QQC2.CheckBox {
            id: allPopupBox
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.largeSpacing
            onToggled: page.setAllPopupGraphs(checked)
        }
        // Bindings survive user clicks (a plain "checked:" binding would be dropped).
        Binding { target: allPanelBox; property: "checked"; value: page.allPanelGraphs }
        Binding { target: allPopupBox; property: "checked"; value: page.allPopupGraphs }

        QQC2.CheckBox {
            id: fanAnimate
            visible: page.hasFan
            Layout.columnSpan: 5
            Layout.topMargin: Kirigami.Units.largeSpacing
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
            Layout.columnSpan: 4
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
