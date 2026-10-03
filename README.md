# LiveNow

A personal task-management app (GTD-style): actions chained by previous/next dependencies, a
calendar, and "growth directions" that measure whether your actions keep the important areas of
life in balance. It replaces a Notion prototype with a fast, reliable, offline-first app.

**Status:** Windows desktop MVP. An iOS "remote controller" app and cross-device sync are
planned but not started — the local schema is already designed for that (see
[Architecture](#architecture)).

## Features

- **Actions** (one section, three switchable views)
  - **Current Actions** — a Done Before / Not Done Yet board with hover toolbar (Start, Finish,
    Continue, postpone, delete), marquee and Ctrl/Shift multi-select, and paging for large lists.
  - **Calendar** — time grid with a 2–7 day range (keys `2`–`7`), drag to move, resize an event
    across days, drag on empty space to create, **Shift/Ctrl+drag to rubber-band select**, group
    move/delete, zoom (Ctrl +/−/wheel). **Today** scrolls the red now-line to the middle.
    All-day actions have a checkbox (done, struck through), can be dragged into the time grid
    (duration = the action's average/predicted time, else 1 hour) and Start puts them on the
    now-line; a timed event dragged into a day's all-day strip becomes all-day there.
  - **All** — every action in one list, last edited first by default. Search by name, notes
    and/or growth directions, sort by several fields at once (ascending/descending, e.g. urgency
    then start time) and filter by name, growth directions, previous/next actions, duration and
    urgency.
  - **Import CSV** (upload button next to the tabs) — reads a Notion export of actions (name,
    date/time, next/previous actions, growth directions), links the actions and directions, and
    skips rows that already exist, so re-importing the same file is safe.
- **Edit time anywhere** — click an action's time on a card or list row (or in the action
  editor) to open one editor: type digits, `Ctrl+↑/↓` to raise/lower the focused unit
  (minute/hour/day/month/year, with carry), `←/→` to move between units, `↓/↑` to switch between
  start and end. The cursor starts on the start minutes. Saving from a card or row can be undone.
- **Growth directions** — Balance boards, a List and a **Mindmap** of how directions lead to
  larger goals, each with a target over a rolling window and a computed urgency.
- **Edit menu** — name, a button row (Start, Finish, postpone, delete…), clickable start/end with
  duration and All day, urgency, growth directions, notes, previous/next actions in two columns,
  and manual parameters. Related actions and directions open from every edit menu; `Ctrl+Enter`
  saves.
- Growth directions show their emoji on calendar events and Current Actions cards, urgency is
  shown everywhere as a scales-on-fire icon (hover: "Urgency to Keep in Balance"), and actions can
  be linked to a direction right from the direction's edit menu.
- Hover a growth-direction emoji on an event or card to see the direction's name; the growth
  direction menu shows level, progress with a bar, weight, urgency and the fact reached so far.
- **Templates** (searchable, sorted by name ignoring emojis, with Start now / Finish now buttons)
  store a name, average duration, notes and growth directions; they affect growth
  directions only after **Use** creates an action. **Import CSV** on the Templates screen loads
  templates from a Notion export. Current Actions colours cards by urgency.
- **Undo** (a toast shown above every dialog, or Ctrl+Z) for destructive and state-changing
  operations, including the buttons inside the edit menu. Postponing to the next morning / after
  work uses the action's own date.
- Light and dark glass look, a collapsible icon-only side bar, and Istanbul wall-clock time for
  all scheduling rules.

## Tech stack

| | |
|---|---|
| App | [Flutter](https://flutter.dev) (Dart), Windows desktop target |
| Local database | SQLite via [Drift](https://drift.simonbinder.eu) |
| State management | [flutter_riverpod](https://riverpod.dev) |
| Planned sync | [PowerSync](https://www.powersync.com) + Postgres (not implemented yet) |

## Getting started

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows/desktop) and
   add its `bin/` folder to `PATH`.
2. Install **Visual Studio 2022** (Community edition is fine) with the **"Desktop development
   with C++"** workload — required to build the Windows target.
3. Enable **Windows Developer Mode** (Settings → Privacy & security → For developers) — required
   for Flutter's Windows build to create symlinks for plugin packages.
4. From `app/`:
   ```
   flutter pub get
   dart run build_runner build   # generates lib/data/database.g.dart from tables.dart
   flutter run -d windows
   ```

If `flutter`/`dart` aren't recognized in a fresh shell, your `PATH` update hasn't propagated to
that shell session yet — open a new terminal, or on Windows reload it in the current one with:
```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
```

## Commands

All run from `app/`:

```
flutter pub get                          # install dependencies
dart run build_runner build              # regenerate lib/data/database.g.dart after editing tables.dart
flutter analyze                          # static analysis
flutter test                             # run all tests
flutter test test/domain/some_test.dart  # run a single test file
flutter run -d windows                   # run the app
flutter build windows --debug            # debug build (fast compile-check)
flutter build windows --release          # release build
```

## Project structure

```
app/
  lib/
    core/       shared helpers (UUIDv7 ids, UTC<->text timestamp codec, settings, stream utils)
    data/       Drift schema, database connection/migrations, live queries behind the views
    domain/     business rules: action lifecycle, dependencies, postpone/done/duration rules,
                growth-direction rules, mindmap layout, CSV parsing and import
    ui/
      providers.dart   Riverpod wiring: database -> services/queries -> widgets
      theme/           glass design tokens and the app theme
      widgets/         reusable pieces (glass surfaces, rail, editors, dialogs, mindmap)
      views/           Current Actions board, Calendar, All
      screens/         shell (rail + sections), Actions section, Growth directions, Templates
  test/         mirrors lib/
dev/            Notion-prototype spec (Actions-Template-Function-Reference.md) and sample data
```

## Architecture

**Layering:** `ui/` → `domain/` (services) → `data/` (Drift/SQLite). The UI never writes SQL
directly except for simple CRUD (templates); every rule about actions, dependencies and growth
directions lives in a domain service, so it's testable independently of any widget and so a
future sync layer doesn't have to re-derive it.

**Schema decisions**, and why (schema version 8):
- **No parent/child task hierarchy.** `action_dependencies` (predecessor/successor — "this must
  happen before that") is the *only* linking mechanism between actions. It's a graph, not a tree.
- **Every table's primary key is a text UUIDv7** (`core/ids.dart`), not an autoincrementing
  integer. Two offline devices creating rows independently can't collide on an ID, and UUIDv7 is
  time-ordered so indexes stay efficient. This is what makes a future PowerSync/Postgres sync
  layer a matter of adding a sync client, not a schema migration.
- **Every timestamp is UTC ISO-8601 text**, not Drift's native integer-based `DateTime` column
  (`core/time_codec.dart`), formatted at a fixed width so plain text ordering agrees with
  chronological order — this matters for the view queries' `ORDER BY`/range filters.
- **Postponing an action moves that same row's time forward**; it doesn't create a new row. An
  `action_occurrences` log records each start/finish/postpone so the history isn't lost to the
  overwrite.
- **"Done" is derived.** `actions.done` is only a manual flag; whether an action counts as done
  for filtering is `domain/done_rule.dart`'s `isDoneBefore()` (computed from the end time for
  scheduled actions), with a SQL twin in `data/queries.dart`.

**Growth directions** (`metrics` table): each direction is boolean, count or hours over a rolling
window against a target. Progress, urgency and weight are computed in `domain/growth_rules.dart`
and `domain/metric_service.dart`; the relation graph between directions must stay acyclic.

**Cycle safety:** `domain/dependency_service.dart` rejects a new predecessor → successor edge if
the successor can already reach the predecessor going forward — i.e. adding it would close a loop.
This is a recursive CTE, run once before the edge is inserted.

**Performance first:** the glass look is drawn from one pre-rendered background image with cheap
per-surface draws (no per-surface blur, clip or gradient), list queries filter and page in SQL
without loading notes, the sections are kept alive instead of rebuilt, and the calendar and
mindmap build only what is visible. `CLAUDE.md` records the measurements and the dead ends.

## Importing actions from CSV

Use the upload button in the Actions section and choose a Notion export with the columns
`Name, Datetime, Next actions and time, Previous actions and time, Growth Direction`. Dates are
day-first (`DD/MM/YYYY`; a date alone makes an all-day action, `DD/MM/YYYY H:mm → H:mm` a timed
one). A summary lists what was created or skipped, directions that could not be matched, and
next/previous references that point to actions that exist nowhere.

## Testing

Domain and query tests run against an in-memory Drift database
(`AppDatabase.forTesting(NativeDatabase.memory())`); widget tests override the database provider
the same way, so no test touches the real on-disk file.

One gotcha if you add a widget test that mounts a screen using a Drift stream: unmounting that
tree must be followed by a pump with a **non-zero** duration (e.g.
`tester.pump(const Duration(milliseconds: 1))`). Drift schedules a zero-duration timer when a
stream subscription is cancelled, and a duration-less pump doesn't advance fake time far enough
for that timer to fire before `flutter_test`'s pending-timer check runs.

## Data and manual UI checks

The app data (SQLite file, theme and side-bar settings) lives in `%APPDATA%\io.livenow\livenow\`.
The schema migrates forward on start and cannot be rolled back, so copy that folder before
installing a build with a newer schema.

When driving the app by script (Win32 `PrintWindow` for screenshots, `SetWindowPos` +
`mouse_event` for clicks), **never run it against your real data**: start it with
`LIVENOW_DATA_DIR=<empty folder>` so every click lands on a throwaway database.
