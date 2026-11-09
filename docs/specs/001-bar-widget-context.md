# Task context: 001-bar-widget

> Generated for prompt-driven run (no spec; standard tier) at HEAD a09e4a8 · 2026-11-09
> Read first by every agent in /anthara:plan-implementer's slice loop.
> No spec exists, so slices below are *provisional work areas* (W1-W6); the planner renames/merges them. Spec-section links are omitted for the same reason.

**De-facto style:** Harbor is a small **layered desktop app**: C++ backend objects (`Backend`, `Theme`, `Translator`, `SelfUsage`) exposed to QML as context properties in `src/main.cpp`; QML is pure view. The new plugin is a **separate deployable** run by Omarchy's Quickshell process. It cannot link or call Harbor's C++. It re-implements a thin docker adapter in QML (`Quickshell.Io` `Process`) and must mirror `Backend`'s contract by convention. That contract is copied, not shared, so keep it small and named.

## 1. Affected modules
| Module / file | Role | Notes |
|---|---|---|
| `omarchy-plugin/` (new, name TBD by planner) | The bar-widget plugin: `manifest.json`, widget QML, `i18n/*.json` | **Greenfield.** No plugin dir exists in the repo. |
| `src/backend.cpp` / `.h` (`Backend`) | The docker CLI contract the plugin mirrors | Read-only reference. Do not change it for the plugin. |
| `src/Main.qml` (`runningCount`, `isRunning`, `stateLabel`, `stateColor`) | Harbor's state vocabulary and running-count logic | Read-only reference. |
| `src/i18n/en.json`, `src/i18n/da.json` | Harbor's catalogs | Source for reused translations. Not loaded by the plugin. |
| `pkgbuild/PKGBUILD` (`package()`) | Arch packaging | Gains install lines for the plugin dir. |
| `pkgbuild/harbor.desktop` | Launcher entry, `Exec=harbor`, `StartupWMClass=harbor` | Target of "Open Harbor". |
| `bin/install`, `bin/build`, `bin/test` | Build/install/test scripts | `bin/test` may gain a plugin check. |
| `README.md` | User docs: intro, Shortcuts, Build | Gains a "Bar widget" section. |
| `tests/harbor_tests.cpp`, `tests/harbor_tests.pro` | QtTest suite, C++ only | Optional catalog-validity test for plugin JSON. |
| `/usr/share/omarchy/shell/` (external, read-only) | Plugin host: `services/PluginRegistry.qml`, `Commons/Translations.qml`, `Ui/*` | The host API the plugin targets. Never edit it. |

## 2. Patterns to follow
- **One docker invocation per concern, run async, failure goes to one string.** `Backend::runDocker` runs `QProcess`, treats exit 0 + `NormalExit` as success, and passes stderr+stdout to `Backend::describeFailure`. `FailedToStart` or an empty path becomes the missing-docker message. Mirror this as one QML `Process` per call.
- **No overlapping refreshes, re-run once.** `Backend::refresh` uses `m_refreshing` / `m_refreshAgain`: a refresh asked for mid-flight runs once after the current one ends, so an action's result is always seen. Superwhisper's `Service.qml` does the same in QML (`_refreshAgain`).
- **Per-container busy guard.** `Backend::perform` ignores an action on an id already in `busyIds`. It marks the id busy, then clears it on completion, then calls `refresh()`. A failure raises `actionFailed(message)` (shown as a toast in Harbor).
- **Action whitelist.** `actionArguments()` (anon namespace in `backend.cpp`) maps action name to argv. Unknown actions are no-ops (test `ignoresUnknownActions`).
- **English source text as catalog key (Harbor)** vs **dotted keys (Omarchy plugins).** See section 3 and W4.
- **Comments explain *why*, in plain prose** (see `Backend::refresh`, `Translator::reload`). Match this tone. No line-noise comments.
- **Omarchy bar widget shape.** Small widget QML using `qs.Commons`, `qs.Ui` (`BarIconButton`, `tooltipText`) and `Process`, as in `/usr/share/omarchy/shell/plugins/bar/widgets/SystemUpdate.qml`. Launch apps with `root.bar.run(cmd)` (`Bar.qml` `run` → `Util.execDetached`). For third-party plugins use `PluginBarApi.qml` `run`.
- AI-ergonomics: `src/Main.qml` (337 lines) holds state labels and colours inline as object literals. The plugin should put its state and label maps in one small `.js` model (as Superwhisper's `Model.js` does) and not scatter `"running"` strings.

## 3. Reusable utilities
- `src/backend.cpp` (`Backend::parseContainers`): the reference parser. One JSON object per line. Lines without `ID` are skipped. Fields are mapped `ID→id`, `Names→name`, `Image→image`, `State→state`, `Status→status`, `Ports→ports`.
- `src/backend.cpp` (`Backend::describeFailure`): the reference error classifier (exact strings in section 4b).
- `/usr/share/omarchy/shell/Commons/Translations.qml`: per-plugin catalogs, `Commons.Translations { directory: Qt.resolvedUrl("i18n") }`, `t(key)`, `tn(key, count)`. Falls back pt-BR → pt → en.json → key. Live language switching.
- `/usr/share/omarchy/shell/Commons/I18n.qml` (`formatNumber`): use it for the count in `tn(...).arg(...)`.
- `/usr/share/omarchy/shell/Commons/Color.qml`, `Style.qml`: theme colours and metrics. Use these, not Harbor's `Theme`.
- `/usr/share/omarchy/shell/Ui/`: `BarIconButton`, `PopupCard`, `Panel`, `PanelController`, `PanelSectionHeader`, `PanelActionButton`, `PanelToolTip`, `Button`, `ConfirmDialog`.
- `/usr/share/omarchy/bin/omarchy-launch-or-focus`: focuses an existing Harbor window or launches one.

## 4. Adjacent code that must coordinate (per work area)
- **W1 (manifest + bar icon/count/tooltip):** `/usr/share/omarchy/shell/services/PluginRegistry.qml` (`validateManifest`, `rescan`, `isSafeEntryPoint`); `~/.config/omarchy/shell.json` (`bar.layout`, where the user places the id).
- **W2 (panel list + start/stop):** `src/backend.cpp` (`actionArguments`, `perform`); `src/Main.qml` (`isRunning`, `stateLabel`).
- **W3 (Open Harbor):** `pkgbuild/harbor.desktop`; `src/main.cpp` (`setDesktopFileName("harbor")`, which makes the Wayland app_id `harbor`).
- **W4 (i18n):** `src/i18n/da.json` (strings to reuse); `Commons/Translations.qml`.
- **W5 (packaging + README):** `pkgbuild/PKGBUILD` (`package()`); `README.md`; `.gitignore`.
- **W6 (tests):** `tests/harbor_tests.cpp` (`bundledCatalogsAreValid`, `fakeDocker`); `bin/test`.

## 4a. Imitation targets
- **W1/W2:** widget shape: mirror `/usr/share/omarchy/shell/plugins/bar/widgets/SystemUpdate.qml` (64 lines; `Process` + `BarIconButton` + `tooltipText` + `bar.run`). Third-party manifest: mirror `~/.config/omarchy/plugins/superwhisper-panel/manifest.json` (`schemaVersion`, `kinds: ["bar-widget"]`, `entryPoints.barWidget`, `barWidget.{displayName,category,allowMultiple,defaultSection}`). Panel and refresh-coalescing in QML: `superwhisper-panel/Service.qml`. Do not copy the 942-line `Panel.qml` size.
- **W2 docker semantics:** mirror `src/backend.cpp` (`refresh`, `perform`, `describeFailure`): same argv, same guards, same error mapping.
- **W4:** catalog shape: mirror `Commons/Translations.qml` header comment (flat JSON per registry code, plural objects keyed by CLDR category).
- **W5:** README section: mirror the superwhisper README "install by symlink" paragraph. Package lines: mirror existing `install -Dm644 ... "$pkgdir/usr/share/..."` lines in `package()`.
- **W6:** greenfield for QML tests (Harbor has none). The only precedent is `superwhisper-panel/tests/qml_logic.py` + `tests/qml/shell.qml`, which drive a real QML file under `quickshell` and fail (not skip) when quickshell is absent.

## 4b. Lexicon
- **Docker list (exact):** `docker ps --all --no-trunc --format '{{json .}}'`. Output is JSON lines. Running is decided by `state === "running"` only; everything else counts as not running (Harbor's start/stop toggle: `Main.qml` `isRunning`). Running count = `containers.filter(c => c.state === "running").length` (`Main.qml` `runningCount`).
- **Container fields:** `id`, `name`, `image`, `state`, `status`, `ports` (lowercase, from `ID/Names/Image/State/Status/Ports`).
- **State names → labels:** `running`→"Running", `exited`→"Stopped", `paused`→"Paused", `restarting`→"Restarting", `created`→"Created", `removing`→"Removing", `dead`→"Dead"; unknown → raw state. Colours (`Main.qml` `stateColor`): running `#4ade80`, paused/restarting `#facc15`, dead `#f87171`, else `#71717a`.
- **Actions:** `start` → `docker start <id>`, `stop` → `docker stop <id>`. Harbor also has `restart`, `remove` (`rm -f`), which are out of scope for the widget. The id is the full `--no-trunc` ID.
- **Refresh interval:** 3000 ms (`Backend` ctor default `refreshInterval = 3000`; README says "every three seconds"). Plus an immediate refresh after each action completes.
- **Docker binary:** resolved via `QStandardPaths::findExecutable("docker")`. Missing → "Docker isn't installed. Install it with: %1" with `%1 = sudo pacman -S docker`.
- **Error detection (case-insensitive substring of trimmed stderr+stdout):** `"permission denied while trying to connect"` → "Docker refused access. Add yourself to the docker group, then log out and back in: %1" (`sudo usermod -aG docker $USER`). `"Cannot connect to the Docker daemon"` → "Docker isn't running. Start it with: %1" (`sudo systemctl enable --now docker`). Empty → "Docker failed without saying why."; otherwise the trimmed raw message.
- **Ids / names:** app id/desktop file `harbor`; launch `harbor` (prefer `omarchy-launch-or-focus harbor`). Plugin id must **not** start with `omarchy.` (reserved). Use a product namespace, e.g. `harbor.containers` (planner to pin). The directory name should equal the id.

## 4c. Traps
- **W1:** (1) do NOT poll faster than 3 s, and do NOT start a `ps` while one is running. Coalesce like `Backend::refresh`, because the bar lives forever and each tick forks docker. (2) do NOT add `docker stats` (excluded by scope, and it blocks ~1 s per call; see `Backend::fetchStats` comment). (3) count only `state === "running"`; `restarting` and `paused` are not running. (4) when docker errors, show an error state in icon and tooltip, not "0 running".
- **W2:** (1) use the full container ID, not the name. (2) guard per-id busy and ignore repeat clicks, like `perform`/`busyIds`. (3) argv array to `Process.command`, never a shell string with interpolated names (injection). (4) refresh after every action, success or failure. (5) no remove/restart buttons, no stats columns.
- **W3:** (1) `harbor` has no single-instance guard (`src/main.cpp`), so a bare `harbor` exec stacks windows. Use `omarchy-launch-or-focus harbor` via `bar.run`. (2) do NOT add IPC or a single-instance mode to Harbor in passing.
- **W4:** (1) Harbor catalogs are keyed by **English source text** (`Translator` contract, `qsTr("Stop")`). Omarchy plugin catalogs are read by `Commons.Translations` by **key**, and Omarchy convention is dotted keys (`I18n.t("bar.pendingUpdates")`). Pick one scheme for the plugin and keep it. Harbor's `.json` files cannot be loaded as-is. Copy the shared strings (Running/Stopped/Start/Stop/error messages) into the plugin's `en.json`/`da.json` with the same Danish wording. (2) plural entries are objects `{"one","other"}`. Harbor uses `%n`, but `Translations.tn` expects `%1` + `.arg(I18n.formatNumber(n))`. Do not copy `%n` across. (3) only `en` and `da` exist. Ship both, no others.
- **W5:** (1) Omarchy scans third-party plugins **only** at `~/.config/omarchy/plugins/<dir>/manifest.json` (`PluginRegistry` `pluginsDir`, `scan_thirdparty`). The first-party dir is Omarchy's own. A package cannot write to `$HOME`, so install read-only to `/usr/share/harbor/omarchy-plugin/` and document the `ln -sfn` step (symlinks are followed by the `"$dir"/*/` glob). (2) do NOT install into `/usr/share/omarchy/shell/plugins` (owned by the omarchy package). (3) `pkgver` is duplicated in `PKGBUILD` and `src/main.cpp` (`setApplicationVersion`). The manifest `version` becomes a third copy, so keep all three in step. (4) entry points must be relative with no `..` (`isSafeEntryPoint`).
- **W6:** (1) do NOT fake a QML test as a C++ test of copied logic. If QML is tested, follow the Superwhisper harness rule: fail when `quickshell` is absent. (2) a cheap, valid addition: extend `bundledCatalogsAreValid`-style checks to parse the plugin's `i18n/*.json` and `manifest.json`.

## 5. Known dragons
- No TODO/FIXME/LEGACY markers in `src/`, `tests/`, `bin/`.
- `/usr/share/omarchy/shell/` is the host. It changes with Omarchy updates and has no stable versioned API beyond `manifest.schemaVersion: 1`. Pin only to what `SystemUpdate.qml` and Superwhisper use.
- The repo has build artefacts in-tree (`build/`, `pkgbuild/pkg`, `pkgbuild/src`, `*.pkg.tar.zst`). They are gitignored; do not commit them.
- No `CLAUDE.md`. Conventions live only in code comments, and section 2 here is the substitute.
- Harbor's QML hard-codes its state colours (`Main.qml` `stateColor`). The plugin should use `Commons.Color` and pair colour with a text label (colour-blind safety).

## 6. Test conventions
- Single QtTest class `HarborTests` in `tests/harbor_tests.cpp`. It compiles `../src/*.cpp` directly (`tests/harbor_tests.pro`). Tests are named as behaviours (`refreshListsContainers`, `explainsKnownDockerFailures`).
- Run: `bin/test` (qmake6 into `build/tests`, `QT_QPA_PLATFORM=offscreen ./harbor_tests`).
- Coverage: `parseContainers`, `parseStats`, `describeFailure`, refresh/actions/bulk/unknown-action/failure via the fake docker, logs, `SelfUsage`, `Theme`, `Translator` (fallback, regional layering, bundled catalogs valid). **No QML is tested.**
- Fake docker: `HarborTests::fakeDocker(QTemporaryDir)` writes a `/bin/sh` script. It logs argv to `calls`, serves `ps.jsonl`/`stats.jsonl` (fixtures `TwoContainers`: running `aaa111` web + exited `bbb222` db; `WebStats`), and fails with the contents of a `fail` file. Helpers: `calls`, `write`, `writeExecutable`. A plugin QML harness can reuse the same script shape by pointing the plugin's docker path at it (so make the docker path overridable).

## 7. Hot paths and performance landmines
- Plugin refresh tick: it runs inside the long-lived Quickshell process for every bar. One `ps` per 3 s, no overlap, no `stats`. Rebuild the list model only when the parsed list changes (`Backend::setContainers` compares before emitting).
- Multiple monitors: each bar instantiates the widget, so N bars means N pollers. Consider one shared poller (e.g. a singleton/service) if the host allows. The planner decides.

## 8. Open uncertainties resolved during orientation
- "Can the plugin reuse Harbor's translations?" Only by copying strings. The formats differ (English-text keys + `%n` vs keyed + `%1`), and the Harbor catalogs are compiled into the binary's qrc, not on disk.
- "Where does Omarchy find a packaged plugin?" Only in `~/.config/omarchy/plugins/` (top level). A packaged copy needs a user symlink (Superwhisper precedent: `ln -sfn <shipped dir> ~/.config/omarchy/plugins/<id>`).
- "How to open Harbor?" `harbor.desktop` `Exec=harbor`, app_id `harbor`. Use `omarchy-launch-or-focus harbor`.

## 8a. Design system
- **Source of truth (plugin):** Omarchy shell. Tokens in `/usr/share/omarchy/shell/Commons/Color.qml` + `Style.qml`. Components in `/usr/share/omarchy/shell/Ui/` (`qmldir`). Path A: follow it, invent nothing.
- **Harbor app (not the plugin's system):** Material style + `Theme` (`src/theme.cpp`: accent from Omarchy `colors.toml`, radius from Hyprland rounding). Do not port it into the plugin.
- **Components to reuse:** `BarIconButton` (icon + `tooltipText`), `PopupCard`/`Panel`/`PanelController` (click-open panel), `PanelSectionHeader`, `PanelActionButton`, `Button`, `PanelToolTip`.
- **Conventions:** dense; theme-driven light/dark via `Commons.Color`; RTL via `I18n.rightToLeft`; per-state colour must be paired with a text label.
- **Per-area UI note:** W1 → `SystemUpdate.qml`; W2 → Superwhisper `Panel.qml` row and action patterns (structure only, not size).

---
## Changelog
- 2026-11-09: generated by code-orienteer from prompt (no spec) at HEAD a09e4a8.
