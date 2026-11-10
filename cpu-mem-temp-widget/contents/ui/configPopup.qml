import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Bound by Plasma to the "Popup" entries in contents/config/main.xml.
    property alias cfg_popupCpu: popupCpu.checked
    property alias cfg_popupMemory: popupMemory.checked
    property alias cfg_popupTempAvg: popupTempAvg.checked
    property alias cfg_popupTempMax: popupTempMax.checked
    property alias cfg_popupCores: popupCores.checked

    property bool cfg_popupCpuDefault
    property bool cfg_popupMemoryDefault
    property bool cfg_popupTempAvgDefault
    property bool cfg_popupTempMaxDefault
    property bool cfg_popupCoresDefault

    Kirigami.FormLayout {
        QQC2.CheckBox {
            id: popupCpu
            Kirigami.FormData.label: i18n("Show in popup:")
            text: i18n("CPU usage")
        }
        QQC2.CheckBox {
            id: popupMemory
            text: i18n("Memory (used / total)")
        }
        QQC2.CheckBox {
            id: popupTempAvg
            text: i18n("CPU temperature (average)")
        }
        QQC2.CheckBox {
            id: popupTempMax
            text: i18n("CPU temperature (hottest core)")
        }
        QQC2.CheckBox {
            id: popupCores
            text: i18n("Per-core temperatures")
        }
    }
}
