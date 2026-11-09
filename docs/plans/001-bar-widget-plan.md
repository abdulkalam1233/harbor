# Plan: 001-bar-widget

> Spec: `none — planned from prompt` (standard tier) · Context: `docs/specs/001-bar-widget-context.md` · Authored: 2026-11-09
> Risk: LOW (new, separately deployed QML plugin; Harbor's binary is untouched; only Docker start/stop, no remove) · Hard floors: none · Fabric standards: unreachable — the standards lookup was blocked in this session, so standards come from code-craft, test-craft and architecture-craft alone

---

# Part 1 — Review this

*Everything a reviewer needs to approve or redirect the approach. If you only read one part, read this one.*

## What we're doing

Harbor gets a widget for Omarchy's top bar. A Docker icon shows how many containers are running, and hovering it shows a tooltip such as "2 of 5 containers running". Clicking it opens a panel listing every container with its state and a Start or Stop button. The panel also has an "Open Harbor" button. The panel shows no CPU or memory figures; those stay in Harbor.

The widget is a separate plugin, written in QML and run by Omarchy's bar, not by Harbor. That is forced by how Omarchy works. The bar loads plugins into its own long-running process, and a plugin cannot call into Harbor's C++. So the widget talks to Docker itself, with the same `docker` commands, the same "is it running" rule and the same error messages as Harbor. It doesn't try to share code with Harbor.

The plugin ships inside Harbor's package. Omarchy only finds plugins under `~/.config/omarchy/plugins/`, and a package cannot write into a home folder. So the package installs the plugin to `/usr/share/harbor/omarchy-plugin/`, and the README gives two commands to switch it on: a link, then `omarchy plugin enable`. This is the same route Superwhisper takes.

## How it breaks down

Slice 1 builds the widget's decisions as plain, tested JavaScript, with no UI. The next two slices put that logic on screen, first the bar icon and then the panel. The last slice ships it in the package and documents it.

| # | Slice | Delivers | Why this tier | Tier |
|---|-------|----------|---------------|------|
| 1 | Model the Docker contract in `Model.js` | Parsing, running count, error classification, command lists, tested headless | Everything else rests on it, and it must match Harbor exactly | `excellent` |
| 2 | Show the count in the bar | Manifest, bar icon with count and tooltip, polling, English and Danish strings | First code against Omarchy's plugin host, with a long-lived poller | `excellent` |
| 3 | Open a panel to start and stop containers | Click-open panel, per-container Start/Stop, error state, Open Harbor | Keyboard and focus behaviour plus action guards | `excellent` |
| 4 | Ship it in the package and document it | `PKGBUILD` install lines, README section, `bin/test` runs the plugin tests | Mechanical, follows existing lines | `fast` |

Slices 2 and 3 edit the same `Panel.qml`. Slice 3 adds the panel to the widget that slice 2 built. It doesn't create a second file.

## Decisions made

**1. The plugin copies Harbor's Docker contract instead of sharing code with it.** Omarchy runs the plugin inside its own QML process, which can't load Harbor's C++. The plugin therefore runs the same commands Harbor does: `docker ps --all --no-trunc --format '{{json .}}'`, `docker start <id>`, `docker stop <id>`. It uses the same running rule (`state === "running"`) and the same error-text matching. *Rejected: adding an IPC mode to Harbor and having the widget query it. The widget would then only work while Harbor is open, and Harbor would gain a server for no other reason.*

**2. All decisions live in a pure `Model.js`, and the QML files only wire it up.** Quickshell's `Process` won't load outside Quickshell itself (checked: `qmltestrunner` fails with `module "Quickshell.Io" plugin "quickshell-ioplugin" not found`). Plain JavaScript tests fine under `qmltestrunner` (checked). Putting parsing, counting, error classification and command building in `Model.js` makes all of it testable. *Rejected: Superwhisper's harness, which drives the real panel under `quickshell` and links Omarchy's shell into a temp directory. It's heavy for a widget this small.*

**3. Each bar polls on its own, every 3 seconds, and refreshes never overlap.** Omarchy does support shared plugin services, but a third-party bar widget has no published way to reach one (`PluginBarApi` exposes none). Superwhisper also polls inside its widget. A `docker ps` every 3 seconds per monitor is cheap, and the "never overlap, re-run once" rule from Harbor's `Backend::refresh` stops pile-ups. *Rejected: a `service` plugin shared by all bars. It needs a second enable step and a private shell API. Revisit if Omarchy publishes a way for third-party widgets to reach their own service.*

**4. "Open Harbor" runs `omarchy-launch-or-focus harbor`.** Harbor has no single-instance guard, so launching it directly would stack windows. `omarchy-launch-or-focus` focuses an open Harbor window or starts a new one. *Rejected: adding single-instance mode to Harbor in passing. That's a separate change.*

**5. Switching the widget on is a documented, user-run step.** The package installs to `/usr/share/harbor/omarchy-plugin/`. The README gives `ln -sfn /usr/share/harbor/omarchy-plugin ~/.config/omarchy/plugins/harbor.containers` and `omarchy plugin enable harbor.containers --before omarchy.tray`. *Rejected: Harbor creating the link on launch. That would write into the user's shell config without asking, and the user has said they want to approve changes to their bar.*

**6. The plugin id is `harbor.containers`, with its own dotted-key catalogs in English and Danish.** Omarchy reserves the `omarchy.` prefix. Its translation loader looks strings up by key and fills `%1` with `.arg()`. Harbor's catalogs are keyed by English text, use `%n`, and are compiled into the binary, so the shared strings are copied with Harbor's Danish wording. *Rejected: loading Harbor's catalogs, which isn't possible because the formats differ and the files aren't on disk.*

## Where this could go wrong

- **The widget drifting from Harbor on what counts as running, or how errors read.** Slice 1's quality checks pin both to Harbor's exact rule and strings, and its tests use the same two-container example as Harbor's suite.
- **Container names reaching a shell.** Names come from Docker and anyone can set them. Slice 1 builds every command as an argument list, and slice 3's quality check forbids `bar.run` with a container value.
- **A poller that never stops, or one that piles up.** Slice 2's quality checks require one refresh in flight at most, and polling only while the widget exists.
- **The plugin silently not loading.** A bad manifest makes Omarchy drop the plugin without an error in the bar. Slice 2's verification enables it in the real bar and reads the shell log.
- **Scope creep into Harbor.** Restart, remove, stats, IPC and single-instance mode all sit next to this work. Every slice's checks keep `src/` unchanged.

## What's out of scope

- CPU and memory figures in the panel (the user's choice of the "Icon + panel" option).
- Restart and remove buttons. Those stay in Harbor.
- Any change to Harbor's app: `src/`, its translations, or single-instance or IPC support.
- Creating the plugin link automatically, from either the package or Harbor.
- A version bump and release. The manifest version follows `pkgver` as it stands, and releasing is a separate step.
- Languages beyond English and Danish, matching Harbor.

---

# Part 2 — Build detail

*Prescriptive detail for the build agent. Reviewers can skim or skip.*

**Confidence markers used below:** `[verified]` = the planner read the code or docs and confirmed it. `[inferred]` = pattern-matched from a sibling implementation, not confirmed — the build agent should check before assuming.

## Shared conventions (all slices)

- **Architecture:** a functional core with an imperative shell. `Model.js` is the pure core. `Panel.qml` is the shell: it owns the `Process`, `Timer`, `BarIconButton` and `KeyboardPanel` and calls the core for every decision. Harbor's own layered app is unchanged.
- **Dependency direction:** `Panel.qml` → `Model.js`. `Model.js` imports nothing, and nothing in `src/` depends on the plugin or the other way round.
- **Module map:**
  - `omarchy-plugin/manifest.json` (new) · plugin identity and entry point · read by Omarchy's `PluginRegistry` `[verified]`.
  - `omarchy-plugin/Model.js` (new) · pure decisions · no dependencies.
  - `omarchy-plugin/Panel.qml` (new) · widget, poller, panel · `qs.Commons`, `qs.Ui`, `Quickshell.Io`, `Model.js` `[verified]`.
  - `omarchy-plugin/i18n/en.json`, `omarchy-plugin/i18n/da.json` (new) · strings · read by `Commons.Translations` `[verified]`.
  - `tests/plugin/tst_model.qml` (new) · `Model.js` tests · `QtTest`.
  - `bin/test` (modify) · also runs `qmltestrunner` on `tests/plugin`.
  - `pkgbuild/PKGBUILD` (modify) · installs the plugin directory.
  - `README.md` (modify) · new "Bar widget" section.
- **Lexicon (from [context §4b](../specs/001-bar-widget-context.md#4b-lexicon) — do not rename):** container fields `id`, `name`, `image`, `state`, `status`, `ports`. State values are Docker's (`running`, `exited`, `paused`, `restarting`, `created`, `removing`, `dead`). Actions are `start` and `stop`. Plugin id `harbor.containers`. Failure kinds `missing`, `denied`, `stopped`, `unknown`.
- **Tests:** `Model.js` is unit-tested with `QtTest` QML under `/usr/lib/qt6/bin/qmltestrunner` (`[verified]`: a `.pragma library` JS import runs offscreen). `Panel.qml` gets no automated test, because `Quickshell.Io` can't load under `qmltestrunner` (`[verified]` probe failure). It is verified in the live bar instead. Harbor's C++ suite (`tests/harbor_tests.cpp`) is unchanged ([context §6](../specs/001-bar-widget-context.md#6-test-conventions)).
- **Design system:** the Omarchy shell (`Commons.Color`, `Style`, `Ui/*`), not Harbor's `Theme` ([context §8a](../specs/001-bar-widget-context.md#8a-design-system)).

---

## Slice 1 — Model the Docker contract in `Model.js`

**Key decision:** all of the widget's decisions go into one pure JavaScript file, so they can be tested without Quickshell (decision 2). The file copies Harbor's Docker contract exactly (decision 1): the list command, the running rule, the error matching and the two actions. Labels stay out of it; it returns keys and counts, and slice 2 turns those into translated text.

**Structure**

- `omarchy-plugin/Model.js` (new), `.pragma library`:
  - `listCommand(): string[]` returns `["docker", "ps", "--all", "--no-trunc", "--format", "{{json .}}"]` `[verified]` (from `Backend`).
  - `actionCommand(action: string, id: string): string[] | null` returns `["docker", action, id]` for `start` or `stop` and a non-empty id. Any other action returns `null`, mirroring `actionArguments()` `[verified]`.
  - `parseContainers(text: string): Container[]` handles one JSON object per line. Lines that are blank, malformed or missing `ID` are skipped. `ID/Names/Image/State/Status/Ports` map to `id/name/image/state/status/ports` `[verified]`. The result is sorted by `name`, ignoring case. `[inferred]`: check the order Harbor's list shows and match it if it differs.
  - `isRunning(container): bool` is true only for `state === "running"` `[verified]`.
  - `runningCount(containers): number` counts the running containers.
  - `failureKind(output: string, failedToStart: bool): string` returns `missing` when `failedToStart` is true. Otherwise it matches the trimmed output ignoring case: `"permission denied while trying to connect"` gives `denied`, and `"cannot connect to the docker daemon"` gives `stopped` `[verified]` (strings from `Backend::describeFailure`). Anything else gives `unknown`.
  - `sameContainers(a: Container[], b: Container[]): bool` compares lists field by field, so the view only rebuilds on real change ([context §7](../specs/001-bar-widget-context.md#7-hot-paths-and-performance-landmines)).
- `tests/plugin/tst_model.qml` (new): a `TestCase` that imports `"../../omarchy-plugin/Model.js" as Model`.

**Collaborators:** none. `Model.js` must not import `Quickshell`, `qs.*` or QtQuick types.

**Control flow:**

- `parseContainers`: split on newlines, then for each line apply three guards in order: skip if blank, skip if JSON parsing fails, skip if `ID` is missing. Map the fields, then sort.
- `failureKind`: check the `failedToStart` guard first, then the two substring checks in the order given, then fall back to `unknown`.

**Tests:** new file `tests/plugin/tst_model.qml`, all unit tests. The fixture is Harbor's two-container example: `aaa111` `web` running and `bbb222` `db` exited ([context §6](../specs/001-bar-widget-context.md#6-test-conventions)). Cases:

- Parses the two-container listing into fields.
- Skips malformed and ID-less lines.
- Counts only running containers, so a restarting or paused container isn't running.
- Classifies the missing, denied, stopped and unknown failures.
- Builds start and stop commands with the id as its own argument.
- Rejects unknown actions and empty ids.
- Treats an equal re-parse as unchanged and a state flip as changed.

**Standards that bite here:** `code-craft`: pure functions, no `null` as control flow except `actionCommand`'s rejection, which mirrors Harbor's no-op. `test-craft`: no logic in test bodies, and names describe behaviour.

**Quality checks**

- **Every command is an argument array, and a container id is always a separate element, never concatenated into a string.**
- The running rule is exactly `state === "running"`, and there is no other running state.
- The error substrings match `Backend::describeFailure` character for character, ignoring case.
- `Model.js` has no imports and no QtQuick or Quickshell references.
- `src/` is unchanged.

**Verification (slice complete when these pass)**

1. **Tests.** Run the full test suite — Harbor's C++ suite and the new plugin tests — all green.

---

## Slice 2 — Show the count in the bar

**Key decision:** this adds the plugin itself. A manifest declares one `bar-widget`, and `Panel.qml` polls Docker and shows a Docker icon with the running count and a tooltip. Polling follows decision 3: every 3 seconds, one `ps` in flight at most, and one queued re-run when a refresh is asked for mid-flight. Strings come from the plugin's own catalogs (decision 6).

**Structure**

- `omarchy-plugin/manifest.json` (new) has `schemaVersion: 1`, `id: "harbor.containers"`, `name: "Harbor"`, `version` equal to `pkgver` in `pkgbuild/PKGBUILD` (currently `0.2.0`), `author`, `license: "MIT"`, `description`, `kinds: ["bar-widget"]` and `entryPoints: { "barWidget": "Panel.qml" }`. `barWidget` holds `displayName`, `description`, `category: "Status"`, `allowMultiple: false` and `defaultSection: "right"`. Shape copied from the Superwhisper manifest `[verified]`.
- `omarchy-plugin/Panel.qml` (new): root `Panel` from `qs.Ui` with `moduleName: "harbor.containers"`, `ipcTarget: "harbor.containers"` and `manageIpc: false` `[verified]` (Tailscale and Superwhisper pattern).
  - Properties: `containers: var` (default `[]`), `failure: string` (`""` when healthy), `refreshing: bool`, `refreshAgain: bool`.
  - Functions: `refresh(): void` and `handleListExit(exitCode: int, stdout: string, stderr: string): void`.
  - Children: `Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }` `[verified]`; `Process { id: listProcess }` with `StdioCollector` for stdout and stderr `[verified]` (Tailscale `Service.qml` pattern); `Timer` (3000 ms, repeat, running, triggered on start); `BarIconButton` with `text: "󰡨"` (U+F0868, Docker glyph, present in JetBrainsMono Nerd Font `[verified]`), `labelText` showing the running count and `tooltipText`.
- `omarchy-plugin/i18n/en.json` and `omarchy-plugin/i18n/da.json` (new): dotted keys. `tooltip.running` is a plural (`one`/`other`) with `%1` and `%2` ("%1 of %2 containers running"). `tooltip.none` is "No containers". Then come `failure.missing`, `failure.denied`, `failure.stopped` and `failure.unknown`, each with `%1` holding the fix command. The Danish text reuses Harbor's `src/i18n/da.json` wording `[verified]`.

**Collaborators:** `Panel.qml` calls `Model.listCommand`, `Model.parseContainers`, `Model.sameContainers`, `Model.runningCount` and `Model.failureKind`. Nothing in the plugin calls Harbor's binary in this slice.

**Control flow:**

- `refresh`: if a refresh is already running, set `refreshAgain` and return. Otherwise set `refreshing` and start `listProcess` with `Model.listCommand()`.
- `onExited`: on exit code 0, parse and assign `containers` only when `sameContainers` is false, and clear `failure`. On a non-zero exit, set `failure` to `Model.failureKind(stderr + stdout, false)`. Then clear `refreshing`, and if `refreshAgain` was set, clear it and refresh once more.
- Process error `FailedToStart`: set `failure` to `missing` and clear `refreshing`. `[inferred]`: check the error signal name on Quickshell's `Process` in `/usr/lib/qt6/qml/Quickshell/Io/quickshell-io.qmltypes` before wiring it.
- Icon state: while `failure` is set, the icon is dimmed, the label is hidden, and the tooltip shows the failure string. While healthy, the label shows the running count and the tooltip shows `tooltip.running` or `tooltip.none`.

**Tests:** none new. The logic is covered by slice 1, and the QML is verified live (decision 2).

**Standards that bite here:** Omarchy plugin guidance: `textFormat: Text.PlainText` on every text that carries Docker data, `strings.tn(...).arg(Commons.I18n.formatNumber(n))` for counts, and no shell strings `[verified]` (plugins.md). `code-craft`: the QML calls the model and holds no parsing or classification of its own.

**Quality checks**

- **At most one `docker ps` is running at any time, and a refresh asked for mid-flight runs exactly once afterwards.**
- The plugin id doesn't start with `omarchy.`, and the manifest `version` equals `pkgver`.
- A Docker error shows the failure state, never "0 running".
- No `docker stats` call exists anywhere in the plugin.
- No string in `Panel.qml` duplicates a check that `Model.js` already makes, such as `"running"`.
- `src/` is unchanged.

**Verification (slice complete when these pass)**

1. **Tests.** Run the full test suite — all green.
3. **User-facing flow.** Link the plugin directory into `~/.config/omarchy/plugins/harbor.containers`, enable it, and confirm all of the following. The bar shows the Docker icon with the right count. The tooltip reads correctly. Stopping a container from Harbor updates the count within about 3 seconds. With Docker stopped, the icon shows the "Docker isn't running" tooltip. The shell log has no QML errors for `harbor.containers`. Undo the link and the enable when done.
4. **Accessibility.** The icon has a tooltip in every state, and the count is not conveyed by colour alone.

---

## Slice 3 — Open a panel to start and stop containers

**Key decision:** clicking the icon opens a `KeyboardPanel` listing every container with a state label and one Start or Stop button. The footer has "Open Harbor", which runs `omarchy-launch-or-focus harbor` (decision 4). Actions use `Model.actionCommand`'s argument list in a `Process`. A container with an action in flight ignores further clicks, and every action ends with a refresh.

**Structure**

- `omarchy-plugin/Panel.qml` (modify):
  - Property `busyIds: var` (default `[]`).
  - Functions: `perform(action: string, id: string): void`, `isBusy(id: string): bool` and `openHarbor(): void`.
  - Children: a `KeyboardPanel { id: panel; content: Component { ... } }` from `qs.Ui` `[verified]` (API: `open`, `content`, `loadedContent`, `close()`), opened from the `BarIconButton`'s `onPressed`. Copy the wiring from the built-in Tailscale `Panel.qml` `[verified]`.
  - One `Process` per action, created on demand, for example from a `Component`. `[inferred]`: check whether Tailscale reuses a single `Process` or creates them, and copy that approach.
  - Panel content: a header with the title and running count. Then either one row per container (name, image, state label, Start/Stop button) or, when `failure` is set, the failure message with its fix command. Then "No containers" when the list is empty. The footer holds the "Open Harbor" button.
- `omarchy-plugin/i18n/en.json` and `da.json` (modify): add `panel.title`, `action.start`, `action.stop`, `action.openHarbor`, `panel.empty` and the `state.*` labels (`running` = "Running", `exited` = "Stopped", `paused`, `restarting`, `created`, `removing`, `dead`) with Harbor's wording `[verified]`.

**Collaborators:** `Model.actionCommand` and `Model.isRunning`; `bar.run("omarchy-launch-or-focus harbor")` `[verified]` (`PluginBarApi.run` → `Util.execDetached`); `KeyboardPanel` and Omarchy's `Ui` buttons.

**Control flow:**

- `perform`: return early if `isBusy(id)`. Return early if `Model.actionCommand(action, id)` is `null`. Otherwise add the id to `busyIds` and start a `Process` with the argument list. On exit, remove the id from `busyIds` and call `refresh()`, whether the action succeeded or failed. On failure, set `failure` from `Model.failureKind`.
- Button: running containers get Stop and others get Start. While busy, the button is disabled and shows a busy state.
- `openHarbor`: close the panel, then `bar.run` the fixed command.

**Tests:** none new. `actionCommand` is covered in slice 1, and the panel is verified live (decision 2).

**Standards that bite here:** Omarchy plugin guidance: `Text.PlainText` for names, images and states; motion via `Style.duration()`; no animation on open beyond what `KeyboardPanel` provides `[verified]` (plugins.md). `code-craft`: one function per action, no branching on action names outside `Model.js`. WCAG: keyboard-operable rows and buttons, focus visible, state shown as text as well as colour.

**Quality checks**

- **No container name, id or image ever reaches `bar.run` or any shell string. `bar.run` is called only with the fixed `omarchy-launch-or-focus harbor`.**
- A second click on a busy container starts no second `docker` process.
- Every action, successful or failed, is followed by exactly one refresh request.
- The panel offers only Start, Stop and Open Harbor. There is no restart, remove, logs or stats.
- `src/` is unchanged.

**Verification (slice complete when these pass)**

1. **Tests.** Run the full test suite — all green.
3. **User-facing flow.** With the plugin linked and enabled, open the panel from the icon. Stop a running container and start it again. The row and the bar count update without reopening. "Open Harbor" focuses an already-open Harbor window and doesn't open a second one. With Docker stopped, the panel shows the failure message instead of the list. The shell log has no QML errors.
4. **Accessibility.** Keyboard: the panel takes focus when opened, Tab reaches every Start/Stop button and Open Harbor, Escape closes it, and focus is visible on each control. Each row's state is readable as text.

---

## Slice 4 — Ship it in the package and document it

**Key decision:** the package installs the plugin directory read-only to `/usr/share/harbor/omarchy-plugin/`. The README gives the two commands that switch it on and off (decision 5). `bin/test` also runs the plugin tests, so one command covers everything.

**Structure**

- `pkgbuild/PKGBUILD` (modify) `package()`: add `install -Dm644` lines for `omarchy-plugin/manifest.json`, `Model.js`, `Panel.qml`, `i18n/en.json` and `i18n/da.json` under `"$pkgdir/usr/share/harbor/omarchy-plugin/"`, in the style of the existing lines `[verified]`. No new `depends`. `qmltestrunner` ships with `qt6-declarative`, which is already a dependency `[verified]`.
- `bin/test` (modify): after the C++ suite, run `/usr/lib/qt6/bin/qmltestrunner -input "$ROOT/tests/plugin"` offscreen with `QT_QPA_PLATFORMTHEME` unset `[verified]` (probe). Use the same `set -eu` failure behaviour.
- `README.md` (modify): add a "Bar widget" section. It says what the widget shows. It gives the enable commands, `ln -sfn /usr/share/harbor/omarchy-plugin ~/.config/omarchy/plugins/harbor.containers` and `omarchy plugin enable harbor.containers --before omarchy.tray`. It gives the disable path, `omarchy plugin disable harbor.containers` and removing the link. Finally it notes that the plugin needs Omarchy's shell. Superwhisper's README is the precedent `[verified]`.

**Collaborators:** none at runtime.

**Control flow:** none. These are file installs and documentation.

**Tests:** none new. `bin/test` runs slice 1's file.

**Standards that bite here:** keep the README terse and in the existing tone. `PKGBUILD` keeps its existing shape.

**Quality checks**

- **The built package contains the five plugin files under `/usr/share/harbor/omarchy-plugin/` and nothing under `/usr/share/omarchy/` or a home directory.**
- `bin/test` fails when a plugin test fails.
- The README commands use the id `harbor.containers` and the install path exactly as the package does.
- `src/` is unchanged.

**Verification (slice complete when these pass)**

1. **Tests.** Run `bin/test` — the C++ suite and the plugin tests both green.
3. **User-facing flow.** Build the package with `makepkg` and list its contents to confirm the plugin files are there. Follow the README's enable steps against the installed path to confirm the widget appears, then follow its disable steps.

---

## Hard floors

None. No slice touches authentication, authorization, payment, security or migrations. The widget runs `docker start` and `docker stop` with the user's own Docker access and adds no new privilege.

## Escalation log
