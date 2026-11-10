import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Bound by Plasma to the "Graphs" entries in contents/config/main.xml.
    property int cfg_panelGraphStyle
    property alias cfg_popupGraphs: popupGraphs.checked
    property int cfg_historySeconds

    property int cfg_panelGraphStyleDefault
    property bool cfg_popupGraphsDefault
    property int cfg_historySecondsDefault

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: styleBox
            Kirigami.FormData.label: i18n("Panel graphs:")
            model: [i18n("Off"), i18n("Behind text"), i18n("Inline")]
            onActivated: page.cfg_panelGraphStyle = currentIndex
        }
        // Binding survives user input, so "Defaults" keeps updating the box.
        Binding {
            target: styleBox
            property: "currentIndex"
            value: page.cfg_panelGraphStyle
        }

        QQC2.CheckBox {
            id: popupGraphs
            Kirigami.FormData.label: i18n("Popup graphs:")
            text: i18n("Show a graph under each popup item")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.ComboBox {
            id: historyBox
            Kirigami.FormData.label: i18n("History length:")
            textRole: "text"
            valueRole: "value"
            model: [
                { text: i18n("30 seconds"), value: 30 },
                { text: i18n("1 minute"), value: 60 },
                { text: i18n("5 minutes"), value: 300 }
            ]
            onActivated: page.cfg_historySeconds = currentValue
        }
        Binding {
            target: historyBox
            property: "currentIndex"
            value: Math.max(0, historyBox.indexOfValue(page.cfg_historySeconds))
        }

        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 20
            wrapMode: Text.WordWrap
            opacity: 0.7
            text: i18n("History is collected only while a graph is turned on.")
        }
    }
}
