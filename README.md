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

Right-click the widget in the panel and choose **Configure…**:

| Setting | Default |
|---|---|
| Show CPU / memory / temperature | all on |
| Temperature unit | °C |
| Warning threshold (always entered in °C) | 80 |
| Refresh interval | 1000 ms (min 250) |

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

## Layout

```
cpu-mem-temp-widget/
  metadata.json                 widget id, name, API version
  contents/config/main.xml      settings schema and defaults
  contents/config/config.qml    registers the settings page
  contents/ui/main.qml          panel view, popup, sensors
  contents/ui/configGeneral.qml settings page
install.sh / uninstall.sh
```
