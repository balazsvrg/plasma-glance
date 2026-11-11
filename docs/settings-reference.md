# Glance settings reference

Every configuration key declared in `package/contents/config/main.xml`, grouped by where it appears in the settings dialog. The key names, types, defaults and ranges come straight from `main.xml`; the labels come from the three settings pages (`configGeneral.qml`, `configMetrics.qml`, `configGraphs.qml`, registered in `config.qml` as the tabs **General**, **Metrics** and **Graphs**).

Notes that apply to every table:

- The tables below use the widget's own key names (`main.xml`). The name each one has in `~/.config/glancerc` is in the Keys table under "Where the settings are stored".
- "Default" is the value in `main.xml`. The Defaults button in the dialog restores it.
- Ranges (`min`/`max`) are declared in `main.xml` only for some Int keys. In Plasma's applet config, values outside a declared range written by hand are expected to be clamped by Plasma's config layer (not verified); in `glancerc` an out-of-range value is rejected instead (see below); the widget also clamps a few of them itself (noted per key).
- The panel shows only stats that are marked "Show" and, for battery and fan, only when that hardware exists (see `batteryCount` and `fanCount`).
- Stat ids used in several keys: `cpu`, `ram`, `temp`, `freq`, `net`, `bat`, `fan`.


## Where the settings are stored

Since 1.0 the settings live in a text file, `~/.config/glancerc` (the `GenericConfigLocation` of Qt, so `$XDG_CONFIG_HOME/glancerc` when that variable is set). It is an INI file with three sections:

    [Main]       order, fahrenheit, warnTemp, refreshMs, maxLength
    [Metrics]    <id>_show, <id>_popup and each stat's options (<id>_<option>)
    [Graphs]     <id>_panelGraph, <id>_popupGraph, panelStyle, chartStyle, historySeconds

The section is called `Main`, not `General`: QSettings treats `General` as its default group and would write it as `[%General]`. The key names are generated from the metric registry (`Metrics.js`) by `Config.js`, so a new stat gets its keys without any extra step.

How the file and the widget stay in step:

- **At startup** the file is read once. A valid value is applied to the widget. A key the file lacks, or whose value is empty, is written from the widget's current value; this is also how the settings an older version saved in Plasma's own config are carried into the file the first time 1.0 runs. A value that is not valid (wrong type, outside the range, an order with no valid stat id) is left in the file exactly as written, and the widget keeps its current value (the widget issues a `console.warn`, but no log output of it was seen on the author's machine, so do not rely on it).
- **A file that missed writes loses to the widget.** Every change also raises a counter, `settingsRev` in Plasma's config and `rev` in the file's `[Main]` section. If at startup the file's `rev` is lower than the widget's (a write was lost: read-only file, full disk, Plasma killed in the second between the change and the write), the widget's values win and are written back to the file. An equal or higher `rev` lets the file win: hand edits do not touch `rev`, and another instance writing the file raises it. Leave `rev` alone.
- **While the widget runs** every change of a setting (settings dialog, edge drag, Defaults button) is written to the file about a second later (QSettings writes from a timer).
- **Nothing watches the file.** Hand edits are picked up the next time the widget loads (log out and in, `kquitapp6 plasmashell; kstart plasmashell`, or removing and re-adding the widget). Changing a setting in the dialog while the widget runs rewrites that section from the widget's values, so an edit made to the same section in the meantime is lost. Comments are not kept on a rewrite; unknown sections and keys are.
- Plasma's own applet config still holds a copy of every setting, because the settings pages and the rest of the widget read and write through it (see below). The file wins at startup.
- All Glance instances on the machine share this one file.

Values: booleans are `true` / `false` (also `1` / `0`, any case); integers are plain digits within the range below, nothing else (`12.5`, `1e3` and values outside the range are rejected, not clamped). The order is stat ids separated by spaces; an unknown id is ignored, a repeated one is dropped and a missing one is appended in the default order. Do not put commas in a value: an unquoted comma makes QSettings read it as a list.

### Keys

**[Main]**

| Key | Widget setting | Type | Default | Valid values |
|---|---|---|---|---|
| `order` | `statOrder` | list | `cpu ram temp freq net bat fan` | stat ids separated by spaces |
| `fahrenheit` | `useFahrenheit` | bool | `false` | `true`, `false` |
| `warnTemp` | `warnTemp` | int | `80` | 30 to 120 |
| `refreshMs` | `refreshMs` | int | `1000` | 250 to 10000 |
| `maxLength` | `maxLength` | int | `0` | 0 to 5000 |
| `rev` | `settingsRev` | int | `0` | 0 to 2147483647 (change counter, do not edit) |

**[Metrics]**

| Key | Widget setting | Type | Default | Valid values |
|---|---|---|---|---|
| `cpu_show` | `showCpu` | bool | `true` | `true`, `false` |
| `cpu_popup` | `popupCpu` | bool | `true` | `true`, `false` |
| `ram_show` | `showRam` | bool | `true` | `true`, `false` |
| `ram_popup` | `popupMemory` | bool | `true` | `true`, `false` |
| `temp_show` | `showTemp` | bool | `true` | `true`, `false` |
| `temp_popup` | `popupTempAvg` | bool | `true` | `true`, `false` |
| `temp_popupMax` | `popupTempMax` | bool | `true` | `true`, `false` |
| `temp_popupCores` | `popupCores` | bool | `true` | `true`, `false` |
| `freq_show` | `showFreq` | bool | `false` | `true`, `false` |
| `freq_popup` | `popupFreq` | bool | `false` | `true`, `false` |
| `net_show` | `showNet` | bool | `false` | `true`, `false` |
| `net_popup` | `popupNet` | bool | `false` | `true`, `false` |
| `net_bits` | `netBits` | bool | `false` | `true`, `false` |
| `bat_show` | `showBat` | bool | `false` | `true`, `false` |
| `bat_popup` | `popupBat` | bool | `false` | `true`, `false` |
| `bat_separate` | `batSeparate` | bool | `false` | `true`, `false` |
| `fan_show` | `showFan` | bool | `false` | `true`, `false` |
| `fan_popup` | `popupFan` | bool | `false` | `true`, `false` |
| `fan_animate` | `fanAnimate` | bool | `true` | `true`, `false` |

**[Graphs]**

| Key | Widget setting | Type | Default | Valid values |
|---|---|---|---|---|
| `panelStyle` | `panelGraphStyle` | int | `1` | 0 to 2 |
| `chartStyle` | `chartStyle` | int | `1` | 0 to 2 |
| `historySeconds` | `historySeconds` | int | `60` | 30 to 300 |
| `cpu_panelGraph` | `graphPanelCpu` | bool | `false` | `true`, `false` |
| `cpu_popupGraph` | `graphPopupCpu` | bool | `false` | `true`, `false` |
| `ram_panelGraph` | `graphPanelRam` | bool | `false` | `true`, `false` |
| `ram_popupGraph` | `graphPopupRam` | bool | `false` | `true`, `false` |
| `temp_panelGraph` | `graphPanelTemp` | bool | `false` | `true`, `false` |
| `temp_popupGraph` | `graphPopupTemp` | bool | `false` | `true`, `false` |
| `freq_panelGraph` | `graphPanelFreq` | bool | `false` | `true`, `false` |
| `freq_popupGraph` | `graphPopupFreq` | bool | `false` | `true`, `false` |
| `net_panelGraph` | `graphPanelNet` | bool | `false` | `true`, `false` |
| `net_popupGraph` | `graphPopupNet` | bool | `false` | `true`, `false` |
| `bat_panelGraph` | `graphPanelBat` | bool | `false` | `true`, `false` |
| `bat_popupGraph` | `graphPopupBat` | bool | `false` | `true`, `false` |
| `fan_panelGraph` | `graphPanelFan` | bool | `false` | `true`, `false` |
| `fan_popupGraph` | `graphPopupFan` | bool | `false` | `true`, `false` |

A stat's options are the extra switches of its popup and panel: `temp_popupMax`, `temp_popupCores`, `net_bits`, `bat_separate`, `fan_animate`. The keys the widget writes about the hardware and the maximum-length state (`batteryCount`, `fanCount`, `length*`) are not in the file (the change counter `settingsRev` is, as `rev`); they stay in Plasma's config (see "Hidden keys written by the widget").

### Plasma's applet config (still used)

The schema in `main.xml` is unchanged and still drives the settings pages: Glance uses an empty `<kcfgfile name=""/>`, so Plasma keeps the values in the applet's own section of

    ~/.config/plasma-org.kde.plasma.desktop-appletsrc

On the author's machine that file has this shape for the widget (it also holds a `ConfigDialog` group that is not part of `main.xml`) (numbers are per-panel and per-widget instance ids, shown here as N):

    [Containments][N][Applets][N]                      plugin=org.local.cpumemtemp
    [Containments][N][Applets][N][Configuration][General]
    [Containments][N][Applets][N][Configuration][Popup]
    [Containments][N][Applets][N][Configuration][Graphs]

The three config groups match the `<group>` elements in `main.xml`. Keys that still have their default value may be absent from the file. Each placed widget instance has its own section there. The standalone window started with `plasmawindowed org.local.cpumemtemp` uses a different file, `~/.config/plasmawindowed-appletsrc`; where exactly it stores the widget's values was not verified (on the author's machine that file only held a containment entry).

### The plugin ID must never change

The internal plugin ID is `org.local.cpumemtemp` (`package/metadata.json`, `Id`), even though the visible name is "Glance". Plasma links the stored settings to the widget by this ID (the `plugin=` line above). If the ID changed, Plasma would no longer find the settings of the placed widget, and it would start again with the defaults (and treat the old entry as a missing widget).

### Resetting

- One page: open the widget's settings and use **Defaults**; then Apply or OK. This sets every key on that page to its `main.xml` default (and so the file follows). It does not touch the hidden keys below.
- Maximum length only: double-click the edge handle (adjust mode), or set **Maximum length** to "No limit" (0).
- Everything: delete `~/.config/glancerc`, then remove the widget from the panel and add it again; the new instance starts with the defaults. (Deleting only the file is not enough: the widget would write its current values back into a new one.)
- By hand: with Plasma not running, delete the widget's `[Configuration]` sections from `plasma-org.kde.plasma.desktop-appletsrc`. Back the file up first, because it also holds your whole panel and desktop layout.

## General tab

Page: `configGeneral.qml`. A warning box (`LengthNotice`) appears at the top when the maximum length is changing what the strip shows.

| Key | Type | Default | Settings label | What it does / valid values |
|---|---|---|---|---|
| `useFahrenheit` | Bool | `false` | General > "Temperature unit:" (choices "°C", "°F") | `true` shows every temperature in Fahrenheit (choice "°F"). The warning threshold stays in Celsius. |
| `netBits` | Bool | `false` | General > "Network speed unit:" (choices "Bytes per second (MB/s)", "Bits per second (Mb/s)") | `true` shows network speed in bits per second instead of bytes. |
| `warnTemp` | Int | `80` | General > "Warn at or above (°C):" | Temperature in degrees Celsius at or above which the temperature (panel, popup, per-core rows) is shown in the warning colour. Range 30 to 120, step 5 in the spin box. It also sets the top of the temperature graph scale: the scale runs from 20 up to `max(100, warnTemp + 10)`. |
| `maxLength` | Int | `0` | General > "Maximum length (px):" (0 is shown as "No limit") | Longest the panel strip may be, in pixels along the panel (width on a horizontal panel, height on a vertical one). `0` means no limit. Range 0 to 5000, step 10, editable (typed text that is not a number becomes 0). Also written by the edge-drag handle: a drag that moved saves the new length, and resetting the handle writes 0. When the strip is too long, the widget saves space in steps: 0 full text, 1 inline graphs become behind-text graphs, 2 compact text (horizontal panels only), 3 tight spacing, then stats are dropped from the end of `statOrder` (the first stat is never dropped). See the hidden keys below. |
| `refreshMs` | Int | `1000` | General > "Refresh every (ms):" | Sensor update interval in milliseconds. Range 250 to 10000, step 250. The widget also applies `max(250, value)`. It also sets how many points a graph holds (see `historySeconds`). |

## Metrics tab

Page: `configMetrics.qml`. A table with one row per stat. Column headers: "Stat", then under "In the panel" the columns "Show" and "Graph", then under "In the popup" the columns "Show" and "Graph". Rows can be reordered by dragging the handle or with the up/down arrow buttons (tooltips "Move up", "Move down"). The footer row "All graphs" has two checkboxes (panel graph, popup graph) that set every available graph key at once; Battery and Fan rows are skipped while those rows are hidden. A stat that the maximum length is hiding shows the note "hidden by the maximum length".

The table rows are the stat names "CPU usage", "Memory", "CPU temperature", "CPU frequency", "Network speed", "Battery" and "Fan speed". The Battery row appears only when `batteryCount > 0` and the Fan row only when `fanCount > 0`.

### Order

| Key | Type | Default | Settings label | What it does / valid values |
|---|---|---|---|---|
| `statOrder` | String | `cpu,ram,temp,freq,net,bat,fan` | Metrics > row order of the table (drag handle or arrows) | Order of the stats, comma-separated ids with no spaces, used for the panel strip (left to right, or top to bottom on a vertical panel), the popup (top to bottom) and the tooltip. It is also the priority when the maximum length is short: stats at the end are dropped first, and the first one is never dropped. |

How `statOrder` is read (`normalizeOrder` in `main.qml`; the Metrics page's `loadOrder` does the same):

- Unknown ids are ignored, so a typo or a removed stat does not break anything.
- A repeated id is kept only at its first position.
- Ids missing from the list are appended at the end in the default order (`cpu, ram, temp, freq, net, bat, fan`), so a stat added by a later version shows up automatically.
- An empty or missing value gives the default order.

Example: `fan,cpu,cpu,xyz` is read as `fan,cpu,ram,temp,freq,net,bat`. The stored string is only rewritten when the user moves a row; the page then saves all seven ids.

### Panel and popup switches

For each stat the "Show" checkbox in the panel group decides whether it appears in the strip. The popup switches decide whether it appears in the popup. All are Bool.

| Key | Default | Settings label | What it does |
|---|---|---|---|
| `showCpu` | `true` | Metrics > CPU usage row > In the panel > Show | CPU usage in the panel strip. |
| `showRam` | `true` | Metrics > Memory row > In the panel > Show | Memory usage in the panel strip. |
| `showTemp` | `true` | Metrics > CPU temperature row > In the panel > Show | Average CPU temperature in the panel strip. |
| `showFreq` | `false` | Metrics > CPU frequency row > In the panel > Show | Average CPU frequency in the panel strip. |
| `showNet` | `false` | Metrics > Network speed row > In the panel > Show | Network speed in the panel strip. |
| `showBat` | `false` | Metrics > Battery row > In the panel > Show | Battery in the panel strip. Has an effect only when a battery exists. |
| `showFan` | `false` | Metrics > Fan speed row > In the panel > Show | Fan speed in the panel strip. Has an effect only when a fan was found. |
| `popupCpu` | `true` | Metrics > CPU usage row > In the popup > Show | CPU usage in the popup. |
| `popupMemory` | `true` | Metrics > Memory row > In the popup > Show | Memory in the popup. |
| `popupTempAvg` | `true` | Metrics > CPU temperature row > In the popup > Show | Average CPU temperature in the popup. This is the "Show" box of the CPU temperature row. |
| `popupTempMax` | `true` | Metrics > "Hottest core" sub-row (under CPU temperature), popup Show column | Hottest core temperature in the popup. |
| `popupCores` | `true` | Metrics > "Per-core temperatures" sub-row (under CPU temperature), popup Show column | Per-core temperatures in the popup (shown only when the core count is known and above 0). |
| `popupFreq` | `false` | Metrics > CPU frequency row > In the popup > Show | CPU frequency in the popup. |
| `popupNet` | `false` | Metrics > Network speed row > In the popup > Show | Network speed in the popup. |
| `popupBat` | `false` | Metrics > Battery row > In the popup > Show | Battery in the popup. Has an effect only when a battery exists. |
| `popupFan` | `false` | Metrics > Fan speed row > In the popup > Show | Fan speed in the popup. Has an effect only when a fan was found. |

The temperature stat appears in the popup when any of `popupTempAvg`, `popupTempMax` or `popupCores` is on. Sensors that only an optional stat or the popup uses are disabled while the matching switch is off, so nothing polls for data nobody sees.

### Other Metrics tab options

| Key | Type | Default | Settings label | What it does / valid values |
|---|---|---|---|---|
| `fanAnimate` | Bool | `true` | Metrics > "Animate fan icon based on fan speed" (checkbox below the table; visible only when a fan was found, `fanCount > 0`) | Rotates the fan icon at a speed that follows the fan speed. The animation is a stepped timer and runs only while visible and needed. |
| `batSeparate` | Bool | `false` | Metrics > "Popup battery view" (choices "Combined", "Each battery separately"; visible only when `batteryCount > 1`) | `true` lists each battery separately in the popup. It has an effect only with more than one battery. |

### Batteries and fans (hidden keys, shown here for context)

`batteryCount` and `fanCount` are listed under "Hidden keys" below. They decide whether the Battery and Fan rows and the two options above are visible on this tab.

## Graphs

Graph switches are set per stat on the Metrics tab (the "Graph" columns); the Graphs tab holds the two shared options. A graph's history is collected only while at least one graph that shows that stat is enabled, and it starts when the stat's sensor reports its first real number.

### Graphs tab

Page: `configGraphs.qml`.

| Key | Type | Default | Settings label | What it does / valid values |
|---|---|---|---|---|
| `panelGraphStyle` | Int | `1` | Graphs > "Panel graph style:" (choices "Behind text", "Inline") | Where panel graphs are drawn. Stored values: `1` = behind the text, `2` = inline after the text. The page writes the combo-box index plus one, so only 1 or 2 are ever saved. `main.xml` allows 0 to 2; the widget treats anything other than 2 (including an old 0) as behind the text, and the page shows 0 as "Behind text". Inline graphs take panel length; behind-text graphs do not, so under a tight maximum length inline graphs fall back to behind-text (maximum length step 1). |
| `chartStyle` | Int | `1` | Graphs > "Chart style:" (choices "Line", "Bar") | How every graph is drawn, in the panel (behind text and inline) and in the popup. Stored values: `1` = line, `2` = bar. The page writes the combo-box index plus one, so only 1 or 2 are ever saved. `main.xml` allows 0 to 2; the widget treats anything other than 2 as a line, and the page shows it as "Line". Not to be confused with `panelGraphStyle`, which is only where panel graphs sit. The scales and colours are the same in both styles. |
| `historySeconds` | Int | `60` | Graphs > "History length:" (choices "30 seconds", "1 minute", "5 minutes") | How many seconds of history the graphs show. Stored values: `30`, `60` or `300`. Range in `main.xml` is 30 to 300 and the widget clamps to it, so a hand-edited value in between works; the page then shows the nearest of the three presets without changing the stored value. The number of points is `historySeconds * 1000 / refreshMs` (at least 2). |

### Graph switches (Metrics tab)

All Bool, default `false`. A graph needs its stat to be shown: a panel graph does nothing while the stat's panel "Show" box is off (or the hardware is missing), and likewise for the popup.

| Key | Settings label | What it does |
|---|---|---|
| `graphPanelCpu` | Metrics > CPU usage row > In the panel > Graph | Graph for CPU usage in the panel. |
| `graphPanelRam` | Metrics > Memory row > In the panel > Graph | Graph for memory in the panel. |
| `graphPanelTemp` | Metrics > CPU temperature row > In the panel > Graph | Graph for CPU temperature in the panel. |
| `graphPanelFreq` | Metrics > CPU frequency row > In the panel > Graph | Graph for CPU frequency in the panel. |
| `graphPanelNet` | Metrics > Network speed row > In the panel > Graph | Graph for network speed in the panel. |
| `graphPanelBat` | Metrics > Battery row > In the panel > Graph | Graph for battery in the panel. |
| `graphPanelFan` | Metrics > Fan speed row > In the panel > Graph | Graph for fan speed in the panel. |
| `graphPopupCpu` | Metrics > CPU usage row > In the popup > Graph | Graph for CPU usage in the popup. |
| `graphPopupRam` | Metrics > Memory row > In the popup > Graph | Graph for memory in the popup. |
| `graphPopupTemp` | Metrics > CPU temperature row > In the popup > Graph | Graph for the average CPU temperature in the popup. |
| `graphPopupFreq` | Metrics > CPU frequency row > In the popup > Graph | Graph for CPU frequency in the popup. |
| `graphPopupNet` | Metrics > Network speed row > In the popup > Graph | Graph for network speed in the popup. |
| `graphPopupBat` | Metrics > Battery row > In the popup > Graph | Graph for battery in the popup. |
| `graphPopupFan` | Metrics > Fan speed row > In the popup > Graph | Graph for fan speed in the popup. |

The "All graphs" footer row sets all panel graph keys, or all popup graph keys, in one click (skipping Battery and Fan while those rows are hidden).

## Hidden keys written by the widget

These keys are declared in `main.xml` but have no control on any settings page. The widget writes them so the settings pages can describe hardware and layout state that only the running widget knows. They persist in the config file like any other key (a known trade-off), so after a restart they may briefly hold the last session's value until the widget recomputes them.

| Key | Type | Default | Range | Written by | Meaning |
|---|---|---|---|---|---|
| `batteryCount` | Int | `0` | none declared | `syncBatteryCount()` in `main.qml`, on every `newData` event of the power-management engine's `"Battery"` source | Number of batteries found (0 when there is none). Written with `setCfg`, so only when it changed. |
| `fanCount` | Int | `0` | none declared | The `FanDiscovery` loader in `main.qml`, only when discovery has finished with a final result | Number of fans found. Discovery retries for about 30 seconds and needs two identical non-empty scans, so an empty first scan never writes 0 and never overwrites a saved count. |
| `settingsRev` | Int | `0` | 0 to 2147483647 | `SettingsFile.qml`, with every change of a setting | Counter of settings changes. It is also kept in the settings file as `rev` and compared with it at startup (see "Where the settings are stored"). Do not set it by hand. |
| `lengthLevel` | Int | `0` | 0 to 3 | `syncLengthInfo()` in `main.qml`, from the current fit result | Compaction step the maximum length currently forces. 0 none; 1 inline graphs become behind-text graphs; 2 compact text (horizontal panels only; vertical panels skip it); 3 tight spacing. `LengthNotice` shows the "space between stats is tightened" line when this is 3 or more. |
| `lengthTextShort` | Bool | `false` | | `syncLengthInfo()` | `true` when the maximum length currently shortens the panel text (level 2 or more on a horizontal panel; never true on a vertical panel). |
| `lengthDropped` | String | empty | | `syncLengthInfo()` | Comma-separated stat ids hidden because they do not fit, in order (for example `net,bat,fan`). Empty when nothing is hidden. Dropped stats are taken from the end of `statOrder` and the first stat is never dropped. |
| `lengthInlineOff` | Bool | `false` | | `syncLengthInfo()` | `true` when inline panel graphs are currently drawn behind the text because of the maximum length (only when an inline graph would otherwise be visible). |

The four `length*` keys are recomputed (through `Qt.callLater`, from the fit result itself, not from derived properties that may be stale) whenever the fit changes, and are not written while the edge handle is being dragged. They describe the state for the saved `maxLength`.

### Who reads them

- `LengthNotice.qml` (shown at the top of the General and Metrics tabs) reads `lengthLevel`, `lengthTextShort`, `lengthDropped`, `lengthInlineOff` and `maxLength` live through `Plasmoid.configuration`. It shows a warning only when `maxLength > 0` and at least one of them indicates an effect.
- `configMetrics.qml` reads `batteryCount` and `fanCount` the same way to decide whether the Battery and Fan rows, "Animate fan icon based on fan speed" and "Popup battery view" are visible, and `lengthDropped` and `maxLength` to mark rows "hidden by the maximum length".

### Why the pages must not declare `cfg_` properties for them

Plasma binds every `cfg_<key>` property of a settings page to the stored value when the dialog opens, and writes all declared `cfg_` properties back when the user presses Apply or OK. The widget changes these keys while the dialog is open. If a page declared, say, `cfg_lengthDropped`, it would hold the value from the moment the dialog opened, and Apply would write that stale value back over the widget's newer one. The pages therefore read them through `Plasmoid.configuration`, which is live, and declare no `cfg_` or `cfg_*Default` property for them. Every user setting, by contrast, needs a `cfg_<key>` and `cfg_<key>Default` property in its page. As a consequence the battery and fan rows stay hidden in any test harness that loads a page standalone.
