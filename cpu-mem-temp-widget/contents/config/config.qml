import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "preferences-system"
        source: "configGeneral.qml"
    }
    ConfigCategory {
        name: i18n("Metrics")
        icon: "view-list-details"
        source: "configMetrics.qml"
    }
    ConfigCategory {
        name: i18n("Graphs")
        icon: "office-chart-line"
        source: "configGraphs.qml"
    }
}
