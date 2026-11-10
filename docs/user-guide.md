# Glance user guide

Glance is a KDE Plasma 6 panel widget that shows your machine's vital signs in one compact strip:
CPU usage, memory, CPU temperature, and optionally CPU frequency, network speed, battery and fan
speed. Click the strip for a details popup, hover it for a tooltip, and turn on small line graphs
if you want history.

This guide explains what you see and how to change it. For installing, upgrading, uninstalling and
the list of requirements, see [README.md](../README.md#install) (requirements:
[README.md#requirements](../README.md#requirements)).

Contents:

1. [The three views: strip, popup, tooltip](#the-three-views-strip-popup-tooltip)
2. [The stats](#the-stats)
3. [Colours and alerts](#colours-and-alerts)
4. [Graphs](#graphs)
5. [Maximum length](#maximum-length)
6. [Order and what is hidden first](#order-and-what-is-hidden-first)
7. [Horizontal and vertical panels](#horizontal-and-vertical-panels)
8. [Settings, task by task](#settings-task-by-task)
9. [Troubleshooting](#troubleshooting)

To open the settings, right-click the widget in the panel and choose **Configure...**. There are
three tabs: **General**, **Metrics** and **Graphs**.

---

## The three views: strip, popup, tooltip

### The panel strip

The strip is what lives in your panel. On a horizontal panel it is one line, with a thin divider
between stats:

```
CPU 4%  |  RAM 30%  |  35°C  |  ↓12 KB/s ↑3 KB/s  |  BAT 62% ↑
```

On a vertical panel each stat is a small block with its name above its value (see
[Horizontal and vertical panels](#horizontal-and-vertical-panels)).

Each stat reserves room for its widest possible text, so the strip does not wobble in width when a
number gains a digit.

By default the strip shows CPU usage, memory and temperature. If you switch every stat off in the
panel, the strip shows a single dash (`–`).

### The popup

Click the strip to open the popup; click again (or click elsewhere) to close it. The popup lists the
stats you enabled under **In the popup** in the Metrics tab, in your chosen order, one block per
stat, with names lined up in a column. It shows more detail than the strip:

| Block | What it shows |
|---|---|
| CPU usage | The percentage, plus an optional graph. |
| Memory | `used / total (percent)`, for example `6.2 GiB / 15.4 GiB (40%)`. GiB are binary (1 GiB = 1024^3 bytes). |
| CPU temperature | Rows you can switch on or off individually: **CPU temp (avg)**, **CPU temp (max core)**, and a **Per core** list (`Core 1`, `Core 2`, ... in two columns). Cores that are threads of the same physical core report the same temperature. |
| CPU frequency | The current frequency, plus a `Min / max` row in GHz. |
| Network speed | `Download` and `Upload` rates, each followed by the total transferred (`... total`). |
| Battery | Percentage (with an arrow while charging or discharging) and the energy held in Wh; a `Charging` or `Discharging` row with the time estimate (`3h 12m to full`, `45m left`, or `estimating...`); with several batteries and **Each battery separately** chosen, one line per battery with its percentage, energy, `health` (the battery's remaining capacity) and arrow. |
| Fan speed | The fan icon and the RPM. |

If you have switched everything off, the popup says "Nothing to show. Enable items under
Configure > Metrics."

### The tooltip

Hover the strip to see a tooltip. Its title is "System stats" and below it is one line listing
every stat you have switched on for the panel, in your order, written out in full (never
shortened), separated by `·`. Stats that the maximum length has hidden from the strip are still
listed here, so the tooltip is the place to see everything. Stats you have switched off are not
listed. The tooltip is built from the same order as the strip and the popup.

---

## The stats

All values refresh at the interval set in General (default 1000 ms), except the battery, which the
power-management service reports about every 5 seconds regardless of that setting.

A value that cannot be read (sensor missing, or not reported yet) shows `--` (for example
`CPU --%`, `-- GHz`) rather than a false 0. Give a sensor a few seconds after the widget loads.

| Stat | Panel text | What the number means | On by default |
|---|---|---|---|
| CPU usage | `CPU 4%` | Overall CPU load, all cores combined, 0 to 100%. | Panel and popup |
| Memory | `RAM 30%` | Share of physical memory in use. The popup adds used and total in GiB. | Panel and popup |
| CPU temperature | `35°C` | The **average** temperature across the CPU. The popup can also show the hottest core and every core. | Panel and popup |
| CPU frequency | `2.2 GHz` | The **average** current clock speed across the cores, always in GHz (`0.8 GHz` when idle). | Off |
| Network speed | `↓12 KB/s ↑3 KB/s` | Current download and upload rates, **all network interfaces combined**. | Off |
| Battery | `BAT 62% ↑` | Combined charge of all batteries. `↑` while charging, `↓` while discharging, no arrow otherwise. | Off |
| Fan speed | fan icon and `2400 RPM` | The speed of the **fastest** fan found, with a small fan icon. | Off |

Notes per stat:

- **Temperature unit.** Show `°C` or `°F` in General. The warning threshold is always entered in
  degrees Celsius, whatever unit you display.
- **Network units.** Rates use decimal units (1 KB = 1000 bytes) and roll over to the next unit
  instead of showing `1000 KB/s`. In General you can choose bytes per second (`B`, `KB`, `MB`,
  `GB`) or bits per second (`b`, `Kb`, `Mb`, `Gb`).
- **Battery and fan only exist on machines that have them.** If no battery is found, the Battery row
  does not appear in the Metrics tab and nothing shows in the panel or popup. The same goes for
  the fan. Fans are discovered from the system's lm_sensors data, and discovery keeps looking for
  about half a minute after the widget starts, so a fan can appear a little late after login.
- **Fan icon.** The icon reflects the speed. It stands still at 0 RPM or when the speed is unknown.

  | Fan speed | Icon |
  |---|---|
  | Under 2500 RPM | Plain blades, slow spin |
  | 2500 to under 4000 RPM | Medium spin with a faint motion-blur trail |
  | 4000 RPM and over | Fast spin, two blur trails, a soft blurred disc, a small shake and swirling speed lines |

  The spin is deliberately stepped at about 12 frames a second to keep it cheap, and it runs only
  while the icon is visible and the fan is turning. You can switch the animation off (the icon is
  then a plain still fan); see [Settings](#settings-task-by-task).

---

## Colours and alerts

Normally text uses your theme's text colour. Two things turn red (your theme's "negative" colour):

| Trigger | What turns red |
|---|---|
| Temperature is at or above the warning threshold (default 80 °C, set in General) | In the strip: the temperature, based on the **average** temperature. In the popup: the average row when the average is at or above it, the "max core" row when the hottest core is, and each core in the per-core list when that core is. Each value is judged by its own number, so a red number always matches what is written next to it. |
| Battery is below 15% and not charging | The battery text in the strip and in the popup's battery row. The 15% level is fixed (not configurable). |

Graph lines follow the same colour: a graph for temperature or battery turns red while that
stat is in alert. Otherwise graph lines use your theme's highlight colour. On a light colour
scheme the lines are drawn slightly darker so they stay readable against the light background.

---

## Graphs

Graphs are small line charts of recent history for a stat. They are off by default. Turn them on
per stat in the Metrics tab; there is one **Graph** checkbox for the panel and one for the popup
on each row, and an **All graphs** row at the bottom that sets every one of them at once.

### Where graphs appear

- **In the panel**, next to or behind the stat's text, in one of two styles (Graphs tab):
  - **Behind text** (default): a faint line fills the background of the stat's cell. It takes no
    extra space.
  - **Inline**: a small graph, about four grid units wide, drawn after the text (below the text on
    a vertical panel). It makes the strip longer.
- **In the popup**, as a wider graph under the stat's rows. The temperature graph belongs to the
  "CPU temp (avg)" row, so it only appears while that row is shown.

The network graph has two series (download, and upload in a second colour).

### Chart style

The **Chart style** option (Graphs tab) is **Line** (default) or **Bar**. It applies to every graph,
in the panel (behind the text and inline) and in the popup. The scales, colours (including the red
alert colour) and the newest-sample-on-the-right layout are the same in both styles.

In **Bar** mode neighbouring samples are merged so that every bar stays at least 2 px wide with a
1 px gap, and a bar shows the mean of the samples it covers. A wide popup graph therefore shows more
(and wider) bars than a small panel one. The network graph stacks its bars: download at the bottom,
upload on top in its own colour, so the scale covers the sum of the two. Bars are collected from the
moment Bar is chosen, so after switching from Line a graph starts empty and fills over the history
length.

### Scales

| Stat | Graph scale |
|---|---|
| CPU usage, memory, battery | 0 to 100% |
| Temperature | 20 °C up to 100 °C, or your warning threshold plus 10 if that is higher |
| CPU frequency | 0 up to the highest reading of the CPU's maximum-frequency sensor seen so far, never below 1 GHz |
| Network | 0 up to the highest rate seen (download or upload), decaying about 1% per second; never below 100 KB/s. As bars, the scale covers the highest download plus upload instead |
| Fan | 0 up to the highest RPM seen so far (it does not decay), never below 3000 |

### History

The **History length** (Graphs tab) is 30 seconds, 1 minute (default) or 5 minutes. It holds for
any refresh interval. History is collected only for stats that a graph currently shows, and it
starts once that stat's sensor reports a real value. A new graph therefore starts empty, spans the
samples collected so far, and then scrolls with the newest sample on the right. Turning a graph off
discards its history.

Inline graphs are the first thing the maximum length gives up (see below).

---

## Maximum length

If the strip grows too long for your panel, give it a **maximum length**. It is measured along the
panel: width on a horizontal panel, height on a vertical one. `0` means no limit (the default).

### What happens when the strip does not fit

Glance saves space in steps and stops at the first step that fits:

1. **Inline graphs move behind the text.** Behind-text graphs take no length.
2. **Compact text** (horizontal panels only). It stays readable:

   | Full | Compact |
   |---|---|
   | `CPU 8%` | `C 8%` |
   | `RAM 30%` | `R 30%` |
   | `35°C` | `35°` |
   | `2.2 GHz` | `2.2G` |
   | `↓4.5 MB/s ↑3 KB/s` | `↓4.5M ↑3K` |
   | `BAT 14% ↑` | `B 14%↑` |
   | `2400 RPM` | `2400` (next to the fan icon) |

3. **Tighter spacing** between stats.
4. **Stats are dropped from the end of the strip**, one at a time, until it fits. In the default
   order the first to go is Fan, then Battery, Network, Frequency, Temperature and Memory. The
   **first stat in your order is never dropped**, however small the limit.

Dropped stats lose their graphs too, but they still appear in the tooltip and the popup.

### How the settings tell you

When the limit is changing what you see, a yellow warning appears at the top of the **General**
and **Metrics** tabs. It lists exactly what is happening: inline graphs shown behind the text, text
shortened (for example "CPU 8%" shown as "C 8%"), spacing tightened, and which stats are hidden.
In the Metrics table, each hidden stat is marked "hidden by the maximum length". The warning
reflects the saved limit and the widget's current layout, so it updates after you press **Apply**,
not while you type in the field.

### Setting the limit by dragging

1. Right-click the widget and choose **Adjust length with the mouse** (a checkable entry).
2. A coloured handle appears on the strip's free edge:
   - **Right edge** when the widget sits in the left half of the panel;
   - **Left edge** when it sits in the right half.
   - On a vertical panel: the **bottom edge** when the widget is in the top half, the **top edge**
     when it is in the bottom half.

   The handle sits on the edge that is free to move: a widget in the far half of the panel is
   packed toward the end, so the strip grows toward the start.
3. Drag the handle. The strip resizes live, compacting and dropping stats as it goes, and a small
   readout at the top shows the limit in pixels (or "No limit"). The pointer is followed
   directly, so the drag stays steady even though the handle moves as the strip changes.
4. Release to save. What you see on release is what is saved.

Rules worth knowing:

- **Shrinking is deliberate, growing is immediate.** Each step down (more compact, then dropping a
  stat) only happens once the pointer has gone at least halfway from where the current layout fits
  to where the next, shorter one fits. A small nudge never makes the strip jump. Growing back
  happens as soon as a longer layout fits.
- **Snapping.** The limit is snapped to 5 px (never below 20 px), and the saved value is never
  shorter than the layout you were shown.
- **Dragging out to the full length means "no limit".**
- **Double-click the handle to reset to no limit.**
- A plain click on the handle, or a cancelled press, saves nothing; only an actual drag does.
- Adjust mode turns itself off about 12 seconds after you turn it on or after your last drag. The
  timer only pauses while you are dragging; hovering the handle does not reset it. Or untick the
  menu entry to leave it yourself.

You can also type an exact value in **General > Maximum length**.

---

## Order and what is hidden first

The Metrics tab holds the order of the stats. That one order drives the panel strip (left to right,
or top to bottom on a vertical panel), the popup (top to bottom) and the tooltip.

It is also the **priority** order when space is short: stats at the bottom of the list are hidden
first, and the top stat among those you show is never hidden. If a stat matters most to you, put it
at the top.

To change the order, drag a row by its handle in the Metrics table, or use the up and down arrows.
The "Hottest core" and "Per-core temperatures" rows move together with CPU temperature. The arrows
skip rows that are not available (a Battery or Fan row that does not exist on your machine) and are
greyed out at the ends of the list.

---

## Horizontal and vertical panels

**Horizontal panel.** One line: text, thin vertical dividers between stats, and the optional
graphs and fan icon.

**Vertical panel.** Each stat is a block, stacked top to bottom with a thin horizontal divider
between them. The block's first line is a short caption and the next line is the value:

| Stat | Caption | Value line(s) |
|---|---|---|
| CPU usage | `CPU` | `4%` |
| Memory | `RAM` | `30%` |
| Temperature | `Temp` | `35°C` |
| Frequency | `Freq` | `2.2 GHz` |
| Network | `Net` | two lines: `↓12K`, `↑3K` |
| Battery | `Bat` | `62% ↑` |
| Fan | `Fan` | fan icon and the RPM number |

Differences and caveats on a vertical panel:

- The maximum length is the strip's **height**, and its handle is on the top or bottom edge.
- **The compact-text step is skipped**, because shortening text would save no height. The steps are
  full text, inline graphs behind the text, then tight spacing, then dropping stats.
- Instead, a stat's value is shortened only when it is wider than the panel is thick: temperature
  `42°C` becomes `42°`, frequency `2.2 GHz` becomes `2.2G`, battery loses the space before its
  arrow. Captions are always kept. Text that still does not fit is scaled down (to a minimum of
  8 px).
- An inline graph is drawn **below** the text.
- **Less tested.** Vertical layouts cannot be previewed in the standalone window the author uses
  for testing, so the length calculation for vertical panels is an estimate. If a vertical strip is
  a pixel or two off its limit, that is why.

---

## Settings, task by task

Right-click the widget, choose **Configure...**, change things, and press **Apply** (or **OK**).
**Defaults** restores a tab's defaults.

### General tab

| I want to... | Do this |
|---|---|
| Show temperatures in Fahrenheit | **Temperature unit:** choose `°F`. |
| See network speed in bits instead of bytes | **Network speed unit:** choose `Bits per second (Mb/s)` (default is `Bytes per second (MB/s)`). |
| Change when temperatures turn red | **Warn at or above (°C):** set 30 to 120 in steps of 5. Default 80. Always in Celsius. |
| Stop the strip getting too wide | **Maximum length (px):** set 0 to 5000 in steps of 10; you can type a value. `No limit` (0) is the default. You can also [drag a handle](#setting-the-limit-by-dragging). |
| Update values more or less often | **Refresh every (ms):** 250 to 10000 in steps of 250. Default 1000. Lower is livelier but uses a little more CPU. |

The maximum-length warning (if any) appears above these controls.

### Metrics tab

One table, one row per stat, with a column of checkboxes **In the panel** (**Show**, **Graph**) and
**In the popup** (**Show**, **Graph**).

| I want to... | Do this |
|---|---|
| Show or hide a stat in the strip | Tick or untick **Show** under **In the panel**. |
| Show or hide a stat in the popup | Tick or untick **Show** under **In the popup**. |
| Add a graph to a stat in the strip or popup | Tick **Graph** under the matching group. Style and length are on the [Graphs tab](#graphs-tab). |
| Turn all graphs on or off | Use the **All graphs** row at the bottom (one checkbox for the panel, one for the popup). |
| Change the order, or what is hidden first | Drag the row's handle, or use the up and down arrows. See [Order](#order-and-what-is-hidden-first). |
| Show the hottest core or each core in the popup | Under CPU temperature, tick **Hottest core** and **Per-core temperatures** (popup only). The popup's CPU temperature block shows when any of its three checkboxes is on. |
| Turn the fan icon animation off | Untick **Animate fan icon based on fan speed**. This option appears only if a fan was found. |
| See each battery on its own in the popup | Set **Popup battery view** to **Each battery separately** (default **Combined**). Appears only when more than one battery was found. The strip always shows the combined percentage. |
| Find out why a stat is missing from the strip | Look for the warning at the top and "hidden by the maximum length" beside the stat. See [Maximum length](#maximum-length). |

Defaults: CPU usage, memory and CPU temperature are on in the panel and the popup; frequency,
network, battery and fan are off. The hottest-core and per-core rows are on. All graphs are off.
Battery and Fan rows are hidden if the widget did not find that hardware. Turning off per-core
temperatures also stops the widget reading those sensors, and optional stats' sensors are only read
while something shows them.

### Graphs tab

| I want to... | Do this |
|---|---|
| Draw panel graphs faintly behind the text, using no space | **Panel graph style:** `Behind text` (default). |
| Draw panel graphs as a small chart next to the text | **Panel graph style:** `Inline`. |
| Draw graphs as bars instead of a line | **Chart style:** `Bar` (`Line` is the default). |
| Make graphs show more or less history | **History length:** `30 seconds`, `1 minute` (default) or `5 minutes`. |

Which stats get graphs is chosen on the Metrics tab. The style and history length apply to every
graph.

---

## Troubleshooting

See also [README.md#troubleshooting](../README.md#troubleshooting) for install-time problems.

**The widget is empty or shows only a dash (`–`).**
No stat is switched on for the panel. Open **Configure... > Metrics** and tick **Show** under **In
the panel** for at least one. A single stat is never hidden by the maximum length, so an empty strip
is not caused by that.

**The widget shows "Sorry! There was an error loading ..." or is blank.**
A required Plasma component is missing, or the install is damaged. See
[README.md#troubleshooting](../README.md#troubleshooting) and
[README.md#requirements](../README.md#requirements).

**There is no Battery row in the Metrics tab.**
Glance found no battery (desktop PC, or the power-management service reports none). The row, and
the battery in the strip, appear by themselves once a battery is detected.

**There is no Fan row in the Metrics tab.**
No fan sensor was found. Fans come from lm_sensors (`lmsensors/<chip>/fanN`); install and configure
lm_sensors if your machine has a readable fan. Glance looks for about half a minute after Plasma
starts, so wait, then reopen the settings. If you only see the row after a while following login,
that is why.

**A battery or fan is enabled but nothing shows in the strip.**
The stat is only drawn when the hardware was found. Check the Metrics tab for the row; also check
the maximum-length warning, because Fan and Battery are at the end of the default order and are
the first to be dropped.

**A stat shows `--`.**
The sensor is not available on your machine, or has not reported yet. Wait a few seconds after
the widget loads. If it stays at `--`, KDE's System Monitor probably cannot read that sensor either
(a common case is CPU temperature on hardware without a supported sensor).

**A stat disappeared when I made the strip shorter.**
It was dropped by the maximum length. The settings warning names it. Raise the limit, set it to
`No limit` in General, or move the stat higher in the order on the Metrics tab. It is still in the
tooltip and the popup.

**Text got shortened (`C 8%`, `R`, `2.2G`).**
That is the compact step of the maximum length (horizontal panels). Raise the limit to get the
full text back.

**My graphs are empty.**
A graph starts empty and fills as samples arrive, and it only starts once the sensor has reported a
real value. The panel graph also needs its stat to be shown; a stat dropped by the maximum length
loses its graph.

**My settings were reset.**
Glance's internal plugin ID is `org.local.cpumemtemp` and stays that way on purpose (see
[settings-reference.md](settings-reference.md#the-plugin-id-must-never-change)). Upgrading, or the
rename to Glance in version 0.6, keeps the settings. Settings can start from defaults if you remove the widget from the panel and add it
again, or if you installed a copy with a different plugin ID (for example one you changed
yourself), which Plasma treats as a different widget.

**How do I reload Plasma after installing or upgrading?**
Run `kquitapp6 plasmashell; kstart plasmashell`. This blanks the desktop and panels for a second
or two and does not close your applications. Logging out and in has the same effect. Details:
[README.md#then-load-it-into-plasma](../README.md#then-load-it-into-plasma).

**I want to see the widget in a plain window to check it.**
Run `plasmawindowed org.local.cpumemtemp` in a terminal. Note that it cannot show a vertical panel.
