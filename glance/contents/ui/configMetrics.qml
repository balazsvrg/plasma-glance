import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.plasma.plasmoid

// A table with one row per stat. Rows can be dragged (or moved with the arrow buttons) to set the
// order used in the panel strip and the popup. Each row has Show and Graph checkboxes for the
// panel and for the popup.
KCM.SimpleKCM {
    id: page

    // Bound by Plasma to the entries in contents/config/main.xml.
    property string cfg_statOrder
    property bool cfg_showCpu
    property bool cfg_graphPanelCpu
    property bool cfg_popupCpu
    property bool cfg_graphPopupCpu
    property bool cfg_showRam
    property bool cfg_graphPanelRam
    property bool cfg_popupMemory
    property bool cfg_graphPopupRam
    property bool cfg_showTemp
    property bool cfg_graphPanelTemp
    property bool cfg_popupTempAvg
    property bool cfg_graphPopupTemp
    property bool cfg_popupTempMax
    property bool cfg_popupCores
    property bool cfg_showFreq
    property bool cfg_graphPanelFreq
    property bool cfg_popupFreq
    property bool cfg_graphPopupFreq
    property bool cfg_showNet
    property bool cfg_graphPanelNet
    property bool cfg_popupNet
    property bool cfg_graphPopupNet
    property bool cfg_showBat
    property bool cfg_graphPanelBat
    property bool cfg_popupBat
    property bool cfg_graphPopupBat
    property bool cfg_batSeparate
    property bool cfg_showFan
    property bool cfg_graphPanelFan
    property bool cfg_popupFan
    property bool cfg_graphPopupFan
    property bool cfg_fanAnimate

    property string cfg_statOrderDefault
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
    property bool cfg_batSeparateDefault
    property bool cfg_showFanDefault
    property bool cfg_graphPanelFanDefault
    property bool cfg_popupFanDefault
    property bool cfg_graphPopupFanDefault
    property bool cfg_fanAnimateDefault

    // ---- what each stat is called and which settings belong to it ----
    readonly property var stats: [
        { id: "cpu",  name: i18n("CPU usage"),       show: "showCpu",  graph: "graphPanelCpu",  popup: "popupCpu",      popupGraph: "graphPopupCpu" },
        { id: "ram",  name: i18n("Memory"),          show: "showRam",  graph: "graphPanelRam",  popup: "popupMemory",   popupGraph: "graphPopupRam" },
        { id: "temp", name: i18n("CPU temperature"), show: "showTemp", graph: "graphPanelTemp", popup: "popupTempAvg",  popupGraph: "graphPopupTemp" },
        { id: "freq", name: i18n("CPU frequency"),   show: "showFreq", graph: "graphPanelFreq", popup: "popupFreq",     popupGraph: "graphPopupFreq" },
        { id: "net",  name: i18n("Network speed"),   show: "showNet",  graph: "graphPanelNet",  popup: "popupNet",      popupGraph: "graphPopupNet" },
        { id: "bat",  name: i18n("Battery"),         show: "showBat",  graph: "graphPanelBat",  popup: "popupBat",      popupGraph: "graphPopupBat" },
        { id: "fan",  name: i18n("Fan speed"),       show: "showFan",  graph: "graphPanelFan",  popup: "popupFan",      popupGraph: "graphPopupFan" }
    ]
    function statInfo(id) {
        for (var i = 0; i < stats.length; ++i) if (stats[i].id === id) return stats[i]
        return stats[0]
    }

    // Detected hardware, written by the widget; read live (no cfg_ property, so the dialog never writes them back).
    readonly property int batteryCount: Plasmoid.configuration.batteryCount
    readonly property int fanCount: Plasmoid.configuration.fanCount
    readonly property bool hasBat: batteryCount > 0
    readonly property bool hasFan: fanCount > 0
    function rowAvailable(id) { return id === "bat" ? hasBat : (id === "fan" ? hasFan : true) }
    // Position among the rows that are actually shown, so stripes alternate even when Battery or Fan is hidden.
    function visiblePosition(index) {
        var n = 0
        for (var i = 0; i < index; ++i) if (rowAvailable(orderModel.get(i).statId)) ++n
        return n
    }

    // Is this stat currently hidden by the maximum length? (read live from the widget's state)
    function hiddenByLength(id) {
        var d = Plasmoid.configuration.lengthDropped
        return Plasmoid.configuration.maxLength > 0 && !!d && String(d).split(",").indexOf(id) >= 0
    }

    // ---- a setting by name (the cfg_ properties above) ----
    function cfgGet(key) { return page["cfg_" + key] }
    function cfgSet(key, value) { page["cfg_" + key] = value }

    // ---- the order ----
    ListModel { id: orderModel }
    function loadOrder(text) {
        var all = stats.map(function (s) { return s.id })
        var ids = text ? String(text).split(",") : []
        var seen = []
        orderModel.clear()
        for (var i = 0; i < ids.length; ++i)
            if (all.indexOf(ids[i]) >= 0 && seen.indexOf(ids[i]) < 0) { seen.push(ids[i]); orderModel.append({ statId: ids[i] }) }
        for (var j = 0; j < all.length; ++j)
            if (seen.indexOf(all[j]) < 0) orderModel.append({ statId: all[j] })
    }
    function currentOrder() {
        var ids = []
        for (var i = 0; i < orderModel.count; ++i) ids.push(orderModel.get(i).statId)
        return ids.join(",")
    }
    // The nearest row in direction dir (-1 up, +1 down) that is actually shown, or -1 at the ends.
    function stepTarget(from, dir) {
        for (var i = from + dir; i >= 0 && i < orderModel.count; i += dir)
            if (rowAvailable(orderModel.get(i).statId)) return i
        return -1
    }
    function moveRow(from, to) {
        if (from === to || to < 0 || to >= orderModel.count) return
        orderModel.move(from, to, 1)
        cfg_statOrder = currentOrder()
    }
    // Follow outside changes (the dialog opening, or "Defaults"), but not our own writes.
    onCfg_statOrderChanged: if (cfg_statOrder !== currentOrder()) loadOrder(cfg_statOrder)
    Component.onCompleted: loadOrder(cfg_statOrder)

    // ---- "All graphs" ----
    function allGraphs(popup) {
        for (var i = 0; i < stats.length; ++i) {
            if (!rowAvailable(stats[i].id)) continue
            if (!cfgGet(popup ? stats[i].popupGraph : stats[i].graph)) return false
        }
        return true
    }
    function setAllGraphs(popup, on) {
        for (var i = 0; i < stats.length; ++i) {
            if (!rowAvailable(stats[i].id)) continue          // not shown (no battery / fan): leave its setting alone
            cfgSet(popup ? stats[i].popupGraph : stats[i].graph, on)
        }
    }

    // ---- column sizes, shared by the header, the rows and the sub-rows so everything lines up ----
    readonly property real handleWidth: Kirigami.Units.iconSizes.smallMedium
    readonly property real nameWidth: Kirigami.Units.gridUnit * 20
    readonly property real checkWidth: Kirigami.Units.gridUnit * 3.5
    readonly property real gap: Kirigami.Units.smallSpacing
    readonly property real pad: Kirigami.Units.smallSpacing * 2      // inside the table's outline
    readonly property color outlineColor: Qt.alpha(Kirigami.Theme.textColor, 0.3)

    // A checkbox centred under a column header. It shows `value` and reports a click through
    // toggledTo(on); the Binding keeps the box in step with `value` after the user clicks it.
    component CheckCell: Item {
        id: cell
        property bool value
        signal toggledTo(bool on)
        Layout.preferredWidth: page.checkWidth
        implicitHeight: box.implicitHeight
        QQC2.CheckBox {
            id: box
            anchors.centerIn: parent
            onToggled: cell.toggledTo(checked)
            Binding { target: box; property: "checked"; value: cell.value }
        }
    }
    // A checkbox cell tied to a setting by name.
    component CfgCheck: CheckCell {
        id: cfgCell
        property string key
        value: page.cfgGet(key)
        onToggledTo: function (on) { page.cfgSet(cfgCell.key, on) }
    }
    // An indented popup-only row under a stat (its checkbox sits in the "popup show" column).
    component SubRow: RowLayout {
        id: sub
        property string label
        property string key
        spacing: page.gap
        Item { Layout.preferredWidth: page.handleWidth }
        QQC2.Label { text: sub.label; opacity: 0.8; leftPadding: Kirigami.Units.gridUnit; Layout.preferredWidth: page.nameWidth }
        Item { Layout.preferredWidth: page.checkWidth }
        Item { Layout.preferredWidth: page.checkWidth }
        CfgCheck { key: sub.key }
    }
    // A plain labelled checkbox tied to a setting by name.
    component CfgCheckLabelled: QQC2.CheckBox {
        id: labelled
        property string key
        onToggled: page.cfgSet(key, checked)
        Binding { target: labelled; property: "checked"; value: page.cfgGet(labelled.key) }
    }
    // A stat's name, with a marker when the maximum length is hiding it in the panel.
    component StatName: RowLayout {
        id: sn
        property string name
        property string statId
        readonly property bool hidden: page.hiddenByLength(statId)
        spacing: Kirigami.Units.smallSpacing
        Layout.minimumWidth: page.nameWidth
        Layout.preferredWidth: page.nameWidth
        Layout.maximumWidth: page.nameWidth
        QQC2.Label { text: sn.name }
        Kirigami.Icon {
            visible: sn.hidden
            source: "dialog-warning"
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
        }
        QQC2.Label {
            visible: sn.hidden
            text: i18n("hidden by the maximum length")
            font.italic: true
            color: Kirigami.Theme.neutralTextColor
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        LengthNotice { }

        QQC2.Label {
            text: i18n("Drag a row by its handle, or use the arrows, to reorder. The order is used in the panel (left to right) and in the popup (top to bottom). When space is short, the stats at the bottom are hidden first.")
            wrapMode: Text.WordWrap
            opacity: 0.8
            Layout.fillWidth: true
            Layout.bottomMargin: Kirigami.Units.smallSpacing
        }

        // The table: an outline, view colours inside (a little darker than the window in a dark
        // theme, like Dolphin) and alternating row colours.
        Rectangle {
            id: table
            Layout.fillWidth: true
            implicitHeight: tableContent.implicitHeight + Kirigami.Units.smallSpacing * 2 + border.width * 2
            Kirigami.Theme.inherit: false
            Kirigami.Theme.colorSet: Kirigami.Theme.View
            color: Kirigami.Theme.backgroundColor
            border.width: 1
            border.color: page.outlineColor
            radius: 3
            clip: true

            ColumnLayout {
                id: tableContent
                // Inset by the border width, so the rows and stripes never paint over the outline.
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: table.border.width
                anchors.rightMargin: table.border.width
                anchors.topMargin: table.border.width + Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                // Group headers
                RowLayout {
                    spacing: page.gap
                    Layout.leftMargin: page.pad
                    Item { Layout.preferredWidth: page.handleWidth }
                    QQC2.Label { text: i18n("Stat"); font.bold: true; Layout.preferredWidth: page.nameWidth }
                    QQC2.Label {
                        text: i18n("In the panel"); font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        Layout.preferredWidth: page.checkWidth * 2 + page.gap
                    }
                    QQC2.Label {
                        text: i18n("In the popup"); font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                        Layout.preferredWidth: page.checkWidth * 2 + page.gap
                    }
                }
                RowLayout {
                    spacing: page.gap
                    Layout.leftMargin: page.pad
                    Item { Layout.preferredWidth: page.handleWidth }
                    Item { Layout.preferredWidth: page.nameWidth }
                    Repeater {
                        model: [i18n("Show"), i18n("Graph"), i18n("Show"), i18n("Graph")]
                        delegate: QQC2.Label {
                            required property string modelData
                            text: modelData
                            opacity: 0.8
                            horizontalAlignment: Text.AlignHCenter
                            Layout.preferredWidth: page.checkWidth
                        }
                    }
                }
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: page.outlineColor }      // under the headers

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    interactive: false                    // the page itself scrolls
                    model: orderModel
                    // Rows glide into place as they are reordered.
                    moveDisplaced: Transition {
                        YAnimator { duration: Kirigami.Units.longDuration; easing.type: Easing.InOutQuad }
                    }

                    delegate: Item {
                        id: slot
                        required property int index
                        required property string statId
                        readonly property var info: page.statInfo(statId)
                        readonly property int position: page.visiblePosition(index)   // among the shown rows
                        width: list.width
                        visible: page.rowAvailable(statId)
                        height: visible ? row.implicitHeight : 0
                        z: dragHandle.dragActive ? 10 : 1                              // the dragged row stays on top

                        // The dragged item must be a child of the delegate, not the delegate itself.
                        Item {
                            id: row
                            width: slot.width
                            implicitHeight: content.implicitHeight + Kirigami.Units.smallSpacing * 2

                            // Alternating colours, like Dolphin; the dragged row is highlighted.
                            Rectangle {
                                // The scheme's alternate colour when it differs from the background; some
                                // schemes report the same colour for both, so then blend a little of the text
                                // colour into the background (about what Dolphin's stripes look like).
                                readonly property color stripe:
                                    Kirigami.Theme.alternateBackgroundColor.toString() !== Kirigami.Theme.backgroundColor.toString()
                                        ? Kirigami.Theme.alternateBackgroundColor
                                        : Qt.tint(Kirigami.Theme.backgroundColor, Qt.alpha(Kirigami.Theme.textColor, 0.04))
                                anchors.fill: parent
                                color: dragHandle.dragActive ? Qt.alpha(Kirigami.Theme.highlightColor, 0.3)
                                       : (slot.position % 2 === 0 ? Kirigami.Theme.backgroundColor : stripe)
                            }

                            ColumnLayout {
                                id: content
                                anchors.verticalCenter: parent.verticalCenter
                                x: page.pad
                                width: parent.width - page.pad * 2
                                spacing: 0

                                RowLayout {
                                    spacing: page.gap
                                    Kirigami.ListItemDragHandle {
                                        id: dragHandle
                                        listItem: row
                                        listView: list
                                        Layout.preferredWidth: page.handleWidth
                                        Layout.preferredHeight: page.handleWidth
                                        onMoveRequested: function (oldIndex, newIndex) { page.moveRow(oldIndex, newIndex) }
                                    }
                                    StatName { name: slot.info.name; statId: slot.statId }
                                    CfgCheck { key: slot.info.show }
                                    CfgCheck { key: slot.info.graph }
                                    CfgCheck { key: slot.info.popup }
                                    CfgCheck { key: slot.info.popupGraph }
                                    QQC2.ToolButton {
                                        icon.name: "arrow-up"
                                        enabled: page.stepTarget(slot.index, -1) >= 0
                                        onClicked: page.moveRow(slot.index, page.stepTarget(slot.index, -1))
                                        QQC2.ToolTip.text: i18n("Move up")
                                        QQC2.ToolTip.visible: hovered
                                    }
                                    QQC2.ToolButton {
                                        icon.name: "arrow-down"
                                        enabled: page.stepTarget(slot.index, 1) >= 0
                                        onClicked: page.moveRow(slot.index, page.stepTarget(slot.index, 1))
                                        QQC2.ToolTip.text: i18n("Move down")
                                        QQC2.ToolTip.visible: hovered
                                    }
                                }

                                // Popup-only details of the temperature stat; they move with it.
                                SubRow { visible: slot.statId === "temp"; label: i18n("Hottest core"); key: "popupTempMax" }
                                SubRow { visible: slot.statId === "temp"; label: i18n("Per-core temperatures"); key: "popupCores" }
                            }
                        }
                    }
                }

                // Turn every graph on or off at once.
                Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: page.outlineColor }      // above the footer
                RowLayout {
                    spacing: page.gap
                    Layout.leftMargin: page.pad
                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                    Item { Layout.preferredWidth: page.handleWidth }
                    QQC2.Label { text: i18n("All graphs"); font.bold: true; Layout.preferredWidth: page.nameWidth }
                    Item { Layout.preferredWidth: page.checkWidth }
                    CheckCell { value: page.allGraphs(false); onToggledTo: function (on) { page.setAllGraphs(false, on) } }
                    Item { Layout.preferredWidth: page.checkWidth }
                    CheckCell { value: page.allGraphs(true);  onToggledTo: function (on) { page.setAllGraphs(true, on) } }
                }
            }
        }

        CfgCheckLabelled {
            visible: page.hasFan
            Layout.topMargin: Kirigami.Units.largeSpacing
            key: "fanAnimate"
            text: i18n("Animate fan icon based on fan speed")
        }

        // Only offered when there are several batteries to separate.
        RowLayout {
            visible: page.batteryCount > 1
            Layout.topMargin: Kirigami.Units.largeSpacing
            QQC2.Label { text: i18n("Popup battery view") }
            QQC2.ComboBox {
                id: batViewBox
                model: [i18n("Combined"), i18n("Each battery separately")]
                onActivated: page.cfg_batSeparate = (currentIndex === 1)
            }
            Binding { target: batViewBox; property: "currentIndex"; value: page.cfg_batSeparate ? 1 : 0 }
        }
    }
}
