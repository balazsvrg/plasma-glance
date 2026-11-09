import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    compactRepresentation: PlasmaComponents.Label {
        text: "CPU --%  RAM --  --°C"
        Layout.minimumWidth: implicitWidth
    }

    fullRepresentation: ColumnLayout {
        PlasmaComponents.Label {
            text: "Details coming soon"
        }
    }
}
