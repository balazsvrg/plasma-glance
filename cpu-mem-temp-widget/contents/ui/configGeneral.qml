import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Plasma binds these to the entries in contents/config/main.xml.
    property alias cfg_showCpu: showCpu.checked
    property alias cfg_showRam: showRam.checked
    property alias cfg_showTemp: showTemp.checked
    property bool cfg_useFahrenheit
    property alias cfg_warnTemp: warnTemp.value
    property alias cfg_refreshMs: refreshMs.value

    property bool cfg_showCpuDefault
    property bool cfg_showRamDefault
    property bool cfg_showTempDefault
    property bool cfg_useFahrenheitDefault
    property int cfg_warnTempDefault
    property int cfg_refreshMsDefault

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: showCpu
            Kirigami.FormData.label: i18n("Show:")
            text: i18n("CPU usage")
        }
        QQC2.CheckBox {
            id: showRam
            text: i18n("Memory usage")
        }
        QQC2.CheckBox {
            id: showTemp
            text: i18n("CPU temperature")
        }

        Item { Kirigami.FormData.isSection: true }

        QQC2.ComboBox {
            id: unitBox
            Kirigami.FormData.label: i18n("Temperature unit:")
            model: ["°C", "°F"]
            currentIndex: page.cfg_useFahrenheit ? 1 : 0
            onActivated: page.cfg_useFahrenheit = (currentIndex === 1)
        }

        QQC2.SpinBox {
            id: warnTemp
            Kirigami.FormData.label: i18n("Warn above (°C):")
            from: 30
            to: 120
            stepSize: 5
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
