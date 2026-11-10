import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Plasma binds these to the entries in contents/config/main.xml.
    property bool cfg_useFahrenheit
    property bool cfg_netBits
    property alias cfg_warnTemp: warnTemp.value
    property alias cfg_refreshMs: refreshMs.value
    property alias cfg_maxLength: maxLength.value

    property bool cfg_useFahrenheitDefault
    property bool cfg_netBitsDefault
    property int cfg_warnTempDefault
    property int cfg_refreshMsDefault
    property int cfg_maxLengthDefault

    ColumnLayout {
        Layout.fillWidth: true
        // Full width at the top, like on the Metrics tab (a form's field column would squeeze it).
        LengthNotice { }

        Kirigami.FormLayout {
            Layout.fillWidth: true
            QQC2.ComboBox {
                id: unitBox
                Kirigami.FormData.label: i18n("Temperature unit:")
                model: ["°C", "°F"]
                onActivated: page.cfg_useFahrenheit = (currentIndex === 1)
            }
            // A Binding element survives user input, unlike a plain currentIndex
            // binding, so "Defaults" and external changes keep updating the box.
            Binding {
                target: unitBox
                property: "currentIndex"
                value: page.cfg_useFahrenheit ? 1 : 0
            }

            QQC2.ComboBox {
                id: netUnitBox
                Kirigami.FormData.label: i18n("Network speed unit:")
                model: [i18n("Bytes per second (MB/s)"), i18n("Bits per second (Mb/s)")]
                onActivated: page.cfg_netBits = (currentIndex === 1)
            }
            Binding {
                target: netUnitBox
                property: "currentIndex"
                value: page.cfg_netBits ? 1 : 0
            }

            QQC2.SpinBox {
                id: warnTemp
                Kirigami.FormData.label: i18n("Warn at or above (°C):")
                from: 30
                to: 120
                stepSize: 5
            }

            QQC2.SpinBox {
                id: maxLength
                Kirigami.FormData.label: i18n("Maximum length (px):")
                from: 0
                to: 5000
                stepSize: 10
                editable: true
                // Along the panel: width on a horizontal panel, height on a vertical one.
                textFromValue: function (value) { return value === 0 ? i18n("No limit") : String(value) }
                valueFromText: function (text) {
                    var n = parseInt(text)
                    return isNaN(n) ? 0 : Math.max(0, Math.min(5000, n))
                }
            }

            QQC2.SpinBox {
                id: refreshMs
                Kirigami.FormData.label: i18n("Refresh every (ms):")
                from: 250
                to: 10000
                stepSize: 250
            }
        }
    }
}
