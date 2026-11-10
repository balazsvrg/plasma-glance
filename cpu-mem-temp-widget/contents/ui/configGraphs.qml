import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Bound by Plasma to the "Graphs" entries in contents/config/main.xml.
    property int cfg_panelGraphStyle
    property int cfg_historySeconds

    property int cfg_panelGraphStyleDefault
    property int cfg_historySecondsDefault

    // Index of the preset (30 s, 1 min, 5 min) closest to a stored value, so a
    // hand-edited config never makes the box show a different setting.
    readonly property var historyPresets: [30, 60, 300]
    function nearestHistoryIndex(seconds) {
        var best = 0
        for (var i = 1; i < historyPresets.length; ++i) {
            if (Math.abs(historyPresets[i] - seconds) < Math.abs(historyPresets[best] - seconds))
                best = i
        }
        return best
    }

    Kirigami.FormLayout {
        QQC2.ComboBox {
            id: styleBox
            Kirigami.FormData.label: i18n("Panel graph style:")
            model: [i18n("Behind text"), i18n("Inline")]
            onActivated: page.cfg_panelGraphStyle = currentIndex + 1     // stored as 1 or 2
        }
        // Binding survives user input, so "Defaults" keeps updating the box.
        Binding {
            target: styleBox
            property: "currentIndex"
            value: page.cfg_panelGraphStyle === 2 ? 1 : 0                // an old 0 shows as "Behind text"
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
            value: page.nearestHistoryIndex(page.cfg_historySeconds)
        }
    }
}
