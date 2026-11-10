# Development guide

For contributors to Glance, the KDE Plasma 6 panel widget. The user-facing documentation is in
[README.md](../README.md); the detailed code conventions are in [architecture.md](architecture.md). This guide covers how to set up, run, test, change and release the widget.

## Prerequisites

- KDE Plasma 6 (developed on 6.8; `metadata.json` declares 6.0 as the minimum). Plasma 5 does not work.
- The Plasma / KDE Frameworks 6 components listed in the README requirements table (sensors, quickcharts,
  kitemmodels, plasma5support, kirigami, kcmutils). Without one of them the widget shows a "There was an
  error loading" message.
- Tools used by the scripts: `kpackagetool6`, `python3` (the scripts read `metadata.json` with it), and
  `zip`, `unzip`, `du` (only `package.sh`).
- Tools used for testing: `plasmawindowed`, `spectacle` (screenshots), `kstatsviewer` (sensor ids),
  and for cross-checking values `free`, `top`, `sensors` (lm_sensors) and `upower`.
- No compiler, no build step, no native code: the widget is pure QML (Qt 6, Kirigami,
  `org.kde.ksysguard.sensors`).
- Python `PIL` is handy for sampling pixel colours of screenshots (the project checks colours that way,
  not by eye), but it is optional.

There is no `qmllint` on the reference machine, so there is no linter to install or run. See
"No automated tests, no linter" below.

## Repository layout

```
package/                           the widget package (what gets installed)
  metadata.json                   plugin id, name, version, minimum Plasma API
  contents/config/main.xml        settings schema and defaults
  contents/config/config.qml      registers the settings pages
  contents/ui/main.qml            panel strip, popup, sensors, layout and length logic
  contents/ui/configGeneral.qml   settings page: General
  contents/ui/configMetrics.qml   settings page: Metrics (reorderable table)
  contents/ui/configGraphs.qml    settings page: Graphs
  contents/ui/LengthNotice.qml    settings banner about the maximum length
install.sh / uninstall.sh         install, upgrade and remove for the current user
package.sh                        builds dist/<id>-<version>.plasmoid
dist/                             build output, not tracked by git
docs/                             documentation
```

Most of the logic is in `main.qml` (about 1400 lines). Before adding a stat, changing the layout or
touching the drag handle, read [architecture.md](architecture.md)
(section 14 is the add-a-stat checklist): they list every place a new stat must be added to, and the helper functions (`statText`, `reservedWidth`, `cellLength`, `layouts`,
`setCfg`...) that the panel, the length calculation and the tooltip must all share.

Two rules from there that catch contributors out:

- Every user setting in `main.xml` needs a matching `cfg_*` property and `cfg_*Default` in its settings
  page. The exception is the keys the widget writes itself (see "Hidden config keys" below).
- Use named enums (`PlasmaCore.Types.Vertical`), not magic numbers.

## The plugin ID must not change

The visible name is "Glance", but the plugin ID stays `org.local.cpumemtemp` on purpose: Plasma stores a
panel widget's settings under it (why, and what a change would do:
[settings-reference.md](settings-reference.md#the-plugin-id-must-never-change)). The ID also appears in
the install folder (`~/.local/share/plasma/plasmoids/org.local.cpumemtemp/`), in `plasmawindowed
org.local.cpumemtemp` and in the package file name. The scripts read it from `package/metadata.json`
(`KPlugin.Id`), the single place it is defined; do not hard-code it elsewhere. Change the display name
and description freely; leave `Id`.

## Running the widget

```
plasmawindowed org.local.cpumemtemp
```

This opens the widget in a plain window, using the installed copy (or, see below, a test copy). It is
the fastest way to see a change. Limits:

- It cannot simulate a vertical panel. The vertical branches of the layout code (`cellLength`,
  `verticalLines`, `verticalWidth`) are estimates that can only be checked in a real vertical panel.
- It shows the popup-style or compact view like a window, not like a panel, so the panel strip's edge
  handle (`MouseArea` handlers) and the choice of handle side cannot be exercised properly.
- Size and thickness come from the window, not from a panel.

Run it from a terminal if you like, but a load failure is drawn in the window, not printed; see the
"Smoke test" section below.

## Testing without touching the real install

`plasmawindowed` loads the widget by its ID from the Plasma data directories. To test a working copy
without installing over the real one, point `XDG_DATA_HOME` at a temporary directory laid out the way
Plasma expects:

```
T=$(mktemp -d)
mkdir -p "$T/plasma/plasmoids"
ln -s "$PWD/package" "$T/plasma/plasmoids/org.local.cpumemtemp"    # or: cp -r package ...
XDG_DATA_HOME="$T" plasmawindowed org.local.cpumemtemp
```

A copy freezes a snapshot (copying `package/` to `$XDG_DATA_HOME/plasma/plasmoids/org.local.cpumemtemp`
makes `plasmawindowed` load that copy; this is the same location `install.sh` uses). A symlink should
pick up your edits on the next launch, but that variant was not verified. If the window shows nothing,
check the folder name equals the `Id` in `metadata.json`. Delete the temporary directory when done.

The normal edit loop with the real install is `./install.sh` and a Plasma reload. Avoid it while
iterating: it replaces your daily widget and restarting Plasma blanks the desktop for a second or two.
Ask before restarting Plasma if you are working with someone else's session.

### Smoke test

1. Launch `plasmawindowed` (as above) and let it run about 5 seconds.
2. Take a screenshot: `spectacle -b -n -a -o /path/to/shot.png` (background, no notification, active
   window, output file).
3. Look at the image.

Rules learned the hard way:

- **An empty stderr proves nothing.** QML load errors (a syntax error, a missing component) are drawn
  inside the widget window, not printed to stderr. Always look at the screenshot after every edit.
  A one-line `if (a) x = y else break` is a QML syntax error that once broke the widget.
- **One `plasmawindowed` test per command.** A second window opened in the same command loses focus,
  and the screenshot then captures the terminal instead.
- **Check the screenshot size** before reading it: the active-window capture should be about 640 px
  wide. If it is the size of your screen, you captured the wrong window.
- Give sensors a few seconds. A stat shows `--` or 0 until its sensor has reported.

### Comparing values with the system

Check the numbers the widget shows against independent tools:

| Stat | Compare with |
|---|---|
| CPU usage | `top` |
| Memory | `free` (used / total) |
| Temperature, fan | `sensors` |
| Frequency, network | `kstatsviewer` and your own tools |
| Battery | `/sys/class/power_supply/BAT*` (`energy_now` / `energy_full`) and `upower -d` |

List the sensor ids KDE offers with `kstatsviewer --list`. The README's Develop section lists the ids the
widget uses.

Battery uses the `powermanagement` data engine (`P5Support.DataSource`), not the ksystemstats
`power/*` sensors, which proved stale and inconsistent on the test laptop. Do not switch it back
without re-verifying against the kernel values above.

## Screenshotting a non-default state

To see something that is not the default view (the popup, a graph style, a config page, a particular
setting), temporarily edit the code, test, and restore:

- Set `preferredRepresentation` in `main.qml` to open the popup view in the window, or
- change a default in `main.xml` (for example a graph style, or turn on a stat).

Then run the smoke test above. **Restore both files afterwards and never commit an override.** Before
every commit, check `git diff` for leftover test code, `Timer`s, on-screen overlays or changed defaults.
A good habit is to do the experiment on a throwaway copy of the file or to `git stash` / `git checkout --
<file>` straight after the screenshot.

## Harness patterns used in this project

There is no way to attach a debugger or read `console.log` conveniently in `plasmawindowed`, and no tool
here can click. So tests are small temporary additions to the QML, driven by themselves:

- **On-screen text instead of `console.log`.** Add a `Text`/`Label` overlay showing the values you care
  about and read it from the screenshot. Example: an overlay printing `layout.implicitWidth` next to
  `stripLength(...)`; they matched exactly at every length step. That is how the length calculation is
  verified against the real layout.
- **Timer-driven drivers.** A temporary `Timer` calls the code under test over time and logs to the
  overlay, for example walking `beginDrag` / `dragTo` through a list of pointer values to check the
  halfway rule of `dragStep()`, or driving the drag handle through the state held in `root`
  (`adjusting`, `dragging`, `dragLength`, `finishDrag()`, `resetLength()`).
- **The order harness (`ordershot.sh` pattern).** To test reordering in the Metrics table, call
  `moveRow()` from a harness. `moveRow()` is the one function both the drag handle and the arrow buttons
  call, so testing it tests both. The `ordershot.sh` script itself is not in the repository; recreate the
  idea as needed.
- **The page harness (`pageshot.sh` pattern).** Set temporary defaults and put a `Loader` that shows a
  config page in place of the popup, so the settings page is visible in the window. Battery and fan rows
  stay hidden there because the page's `cfg_*Count` values are unbound.
- **Colours.** Check them by sampling pixels from the screenshot (PIL `getpixel`), not by eye. Some
  colour schemes make `alternateBackgroundColor` equal to `backgroundColor`, which is why the table
  stripe falls back to blending 4% of the text colour into the background.

All harnesses are throwaway. They live in your working tree only until the screenshot is taken.

## Measuring animation and CPU cost

Animation cost is real. A smooth 60 fps `RotationAnimator` cost about 26% of one core (widget plus
`kwin_wayland`); the 12 fps stepped `Timer` costs about 8.5%. So: keep animations stepped, run them
only while visible and needed, and re-measure when you add one.

Measure with `/proc/<pid>/stat` for the widget and for `kwin_wayland`:

1. Find the pids (`pgrep plasmawindowed`, `pgrep kwin_wayland`).
2. Read fields 14 (`utime`) and 15 (`stime`), in clock ticks, at the start and the end of a fixed
   interval (for example 30 seconds) while the widget shows the animation.
3. CPU share = (ticks end - ticks start) / (`getconf CLK_TCK` * seconds), summed over both processes.
   Compare with the same run with the animation off.

The same reasoning applies to sensors: ones used only by an optional stat or by the popup carry an
`enabled:` tied to the show/popup flags, so nothing polls for data nobody sees. Gate new sensors the same
way.

## No automated tests, no linter

There is no automated test suite and no `qmllint` here. Consequences:

- Verification is manual and visual: the smoke test, harness overlays, and comparison with system tools.
  Report what you actually saw (and say what you could not check), not what you expect.
- A broken file shows up only when the widget loads, so check the window after **every** edit, not only
  at the end.
- Review matters more: for non-trivial changes get a fresh-context review of the plan and the diff
  (`/code-review`) before merging.
- If you can install `qmllint` (Qt 6 declarative tools), running it is welcome, but it is not part of
  the project's process today.

## Change workflow

- Work on a branch, not on the main line. Branch names in the history: `fix/1-freq-width`,
  `fix/8-fan-two-scans`, `docs/full-documentation`, `vertical-thickness`. The main line is
  named `master` in this clone (some tooling assumes `main`); use whichever your clone has.
- One small task per branch; for anything bigger than a small fix, agree a short spec and plan first.
- Small commits. Subject style from `git log`: a short imperative sentence; fixes are prefixed with the
  issue number, for example `Fix #8: fan discovery needs two identical non-empty scans before it is final`,
  followed by a short body that says what changed for the user. Feature steps were
  `Reorder step 1: ...`.
- Merge commits join finished branches, named `Merge fix/8-fan-two-scans`. The maintainer reviews and
  merges; nothing is merged unattended.
- Commit before any bulk or destructive operation. Never force-push or hard-reset without approval.
- Stay in scope: do not refactor or reformat unrelated code in the same change; mention it instead.
- Update the README (and the changelog entry for the next release) when behaviour the user sees changes.

## Releasing

A release is a version bump plus a package. The last two release commits, `Release v0.7` and `Release
v0.8`, each changed exactly two files, `package/metadata.json` and `README.md`, and nothing else (earlier
ones touched the same two files, except `Release v0.2`, which changed only `metadata.json`). Follow the
same steps:

1. **Bump the version** in `package/metadata.json` (`KPlugin.Version`, for example `"0.8"` to `"0.9"`).
2. **Update the README**:
   - the two install-from-package lines that name the file (`org.local.cpumemtemp-0.8.plasmoid`, in "From
     the package", the `-i` and the `sudo ... -g -i` examples);
   - add a new entry at the top of the `## Changelog` section (`**0.9**` followed by bullets, written for
     users).
3. **Commit** as `Release v0.9`.
4. **Build the package**: `./package.sh`. It reads the id and version from `metadata.json`, zips
   `metadata.json` and `contents/` from the working tree (not from a git commit) into
   `dist/org.local.cpumemtemp-0.9.plasmoid`, and lists the files. Make sure the working tree is clean
   first so the package matches the commit.
5. **Validate the package without touching your real install.** Install it into a scratch package root
   and compare with the source:

   ```
   P=$(mktemp -d)
   kpackagetool6 -t Plasma/Applet -i dist/org.local.cpumemtemp-0.9.plasmoid --packageroot "$P"
   diff -r package "$P/org.local.cpumemtemp"
   ```

   `kpackagetool6 --packageroot` installs into `$P/org.local.cpumemtemp`. No output from `diff` means the
   package contains exactly the source. Never run this against the real install.
6. **Install it for real**: `./install.sh`. It installs, or upgrades in place if
   `$XDG_DATA_HOME/plasma/plasmoids/<id>` already exists (`${XDG_DATA_HOME:-$HOME/.local/share}`).
7. **Reload Plasma** so the new version loads: `kquitapp6 plasmashell; kstart plasmashell`. This blanks
   the desktop for a second or two; open applications are unaffected. Ask before doing it.
8. **Tag** the release commit: `git tag -a v0.9 -m "v0.9: ..."`. Every release from `v0.2` on has an
   annotated tag (`v0.7` and `v0.8` were added afterwards, on their release commits).

The author, website and bug-report URL in `metadata.json` point at the GitHub repository. `dist/` is ignored by git; do not commit packages.

## Uninstalling

Remove the widget from your panels first, then:

```
./uninstall.sh                                        # from the repository
kpackagetool6 -t Plasma/Applet -r org.local.cpumemtemp    # same thing by hand
```

and reload Plasma (`kquitapp6 plasmashell; kstart plasmashell`). A system-wide install needs `sudo ... -g -r`.
Uninstalling removes the package but not the saved settings in your Plasma config files.

## Known limitations

- **No real mouse injection.** Nothing in this environment can inject mouse events (no `ydotool` or
  `xdotool`, and `/dev/uinput` is not accessible). The real `MouseArea` handlers, including the
  maximum-length drag handle, are tested only by hand by the maintainer. Drive the state functions with
  a `Timer` for the logic, and say clearly in your report that the pointer handling itself was not
  tested. The handle reads the pointer with `mapToGlobal`, so it stays steady while the handle moves.
- **Vertical panels cannot be tested with `plasmawindowed`.** The vertical branches of `cellLength` are
  estimates. Test on a real vertical panel (move a panel to a screen edge, or add a temporary vertical
  panel) and tell the maintainer what you could and could not see. The handle-side logic
  (`updateHandleSide`, `handleAtStart`) likewise needs a real panel or a forced `handleAtStart`.
- **Hidden config keys persist.** The widget writes six keys itself so the settings pages can read them
  live, and they stay in the user's config file (a known trade-off). Pages must not declare `cfg_`
  properties for them. See [settings-reference.md](settings-reference.md#hidden-keys-written-by-the-widget)
  and [architecture.md](architecture.md) section 7.
- **Fan discovery is slow to settle** (about 30 s of retries; an empty first scan never means "no fan"), so
  test fan code with that in mind. Details: [architecture.md](architecture.md) section 10.
- **Plasma restarts are needed** to load an installed upgrade; `plasmawindowed` loads fresh each time.
- Tested on one machine (Plasma 6.8 on Fedora). Older Plasma 6.x releases and other distributions are
  unverified.
