# CPU / RAM / Temp Monitor

A compact KDE Plasma 6 panel widget that shows CPU usage, memory usage and CPU
temperature in one strip, with a details popup.

```
CPU 4%  |  RAM 30%  |  35°C
```

- Horizontal panels: one line, thin dividers spanning the panel height.
- Vertical panels: three captioned blocks (`CPU` over `4%`), text shrinks to fit.
- Click for a popup with used / total memory, average and max temperature, and a per-core
  temperature list (one entry per KDE core sensor; hyperthreads of one physical core read alike).
- Optional line graphs of all three stats, in the panel (behind text or inline)
  and in the popup. Off by default.
- Each temperature turns red when it reaches the configurable threshold.
- Pure QML. No native code, no background processes: values come from KDE's own
  sensor service (`org.kde.ksysguard.sensors`).

## Requirements

- KDE Plasma 6 (developed on 6.8)
- `kpackagetool6` (ships with Plasma)
- A CPU temperature sensor exposed to KDE System Monitor

## Install

```
./install.sh
kquitapp6 plasmashell; kstart plasmashell    # reload Plasma
```

Then right-click the panel, choose **Add Widgets**, and add
**CPU / RAM / Temp Monitor**. Running `./install.sh` again upgrades in place.

Uninstall with `./uninstall.sh` (remove it from your panels first).

## Settings

Right-click the widget in the panel and choose **Configure…**. There are three tabs.

**General**

| Setting | Default |
|---|---|
| Show CPU / memory / temperature in the panel | all on |
| Temperature unit | °C |
| Warning threshold (always entered in °C) | 80 |
| Refresh interval | 1000 ms (min 250) |

**Popup** (what the click-to-open details show; every item is on by default)

CPU usage, memory (used / total), average temperature, hottest-core temperature,
and per-core temperatures. Turning off the per-core list also stops its sensors.

**Graphs**

| Setting | Default |
|---|---|
| Panel graphs: Off / Behind text / Inline | Off |
| Show a graph under each enabled popup item | off |
| History length: 30 s / 1 min / 5 min | 1 min |

Graph history is collected only for stats that a graph shows, and starts once that stat's
sensor reports a real value, so a missing sensor never blocks the other graphs. The graphs span the samples collected so far and then scroll.
On a vertical panel, "inline" puts the graph below the text.

## Develop

```
kpackagetool6 -t Plasma/Applet -u cpu-mem-temp-widget   # reinstall after edits
plasmawindowed org.local.cpumemtemp                      # test in a plain window
```

`plasmawindowed` cannot simulate a vertical panel. To check that layout, move a
panel to a screen edge or add a temporary vertical panel.

Sensor IDs used (check with `kstatsviewer --list`):
`cpu/all/usage`, `memory/physical/usedPercent`, `memory/physical/used`,
`memory/physical/total`, `cpu/all/averageTemperature`, `cpu/all/maximumTemperature`,
`cpu/all/coreCount`, `cpu/cpuN/temperature`.
Graphs use KDE Quick Charts (`org.kde.quickcharts`: `LineChart`, `HistoryProxySource`).

## Layout

```
cpu-mem-temp-widget/
  metadata.json                 widget id, name, API version
  contents/config/main.xml      settings schema and defaults
  contents/config/config.qml    registers the settings page
  contents/ui/main.qml          panel view, popup, sensors
  contents/ui/configGeneral.qml settings tab: General
  contents/ui/configPopup.qml   settings tab: Popup
  contents/ui/configGraphs.qml  settings tab: Graphs
install.sh / uninstall.sh
```
