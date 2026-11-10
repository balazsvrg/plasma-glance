import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid

// A warning shown in the settings when the maximum length is currently changing what the
// panel strip shows. The widget writes the state (lengthLevel, lengthDropped, lengthInlineOff);
// nothing here has a cfg_ property on purpose, so the dialog never writes them back.
Kirigami.InlineMessage {
    id: notice

    readonly property var cfg: Plasmoid.configuration
    readonly property var droppedIds: cfg.lengthDropped === "" ? [] : String(cfg.lengthDropped).split(",")
    readonly property bool shortened: cfg.lengthLevel >= 2
    readonly property bool active: cfg.maxLength > 0
                                   && (cfg.lengthInlineOff || shortened || droppedIds.length > 0)

    function statName(id) {
        switch (id) {
        case "cpu":  return i18n("CPU usage")
        case "ram":  return i18n("Memory")
        case "temp": return i18n("CPU temperature")
        case "freq": return i18n("CPU frequency")
        case "net":  return i18n("Network speed")
        case "bat":  return i18n("Battery")
        case "fan":  return i18n("Fan speed")
        }
        return id
    }
    function droppedNames() {
        var names = []
        for (var i = 0; i < droppedIds.length; ++i) names.push(statName(droppedIds[i]))
        return names.join(", ")
    }

    Layout.fillWidth: true
    visible: active
    type: Kirigami.MessageType.Warning
    showCloseButton: false
    text: {
        var lines = [i18n("The maximum length (%1 px) is limiting the panel strip:", cfg.maxLength)]
        if (cfg.lengthInlineOff)
            lines.push("• " + i18n("Inline graphs are shown behind the text instead."))
        if (shortened)
            lines.push("• " + i18n("Text is shortened to fit (for example “CPU 8%” shows as “C 8%”)."))
        if (droppedIds.length > 0)
            lines.push("• " + i18n("Hidden because they do not fit, together with their graphs: %1.", droppedNames()))
        lines.push(i18n("Raise the limit, or set it to “No limit” in General, to show everything."))
        return lines.join("\n")
    }
}
