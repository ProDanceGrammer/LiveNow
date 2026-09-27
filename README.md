# LiveNow

A personal task/habit-management app (GTD-style: priorities, recurring habits, and a
previous/next action dependency chain), replacing a Notion prototype with a fast, reliable,
offline-first app.

**Status:** Windows desktop MVP. An iOS "remote controller" app and cross-device sync are
planned but not started — the local schema is already designed for that (see
[Architecture](#architecture)).

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
dart run build_runner build              # regenerate the Drift schema after editing tables.dart
flutter analyze                          # static analysis
flutter test                             # run all tests
flutter test test/domain/some_test.dart  # run a single test file
flutter run -d windows                   # run the app
flutter build windows --release          # release build
```

## Project structure

```
app/
  lib/
    core/       small shared helpers (UUID generation, UTC<->text timestamp codec, app settings)
    data/       Drift schema, database connection, and the live queries behind each view
    domain/     business rules: postpone rules, action lifecycle, dependency graph
    ui/
      providers.dart   Riverpod wiring: database -> services/queries -> widgets
      widgets/         reusable pieces (action tile, create/edit dialog, list view)
      views/           the 5 action views (Operational, TODO, Most Important, Calendar, Habits)
      screens/         top-level screens (the NavigationRail shell, Metrics, Templates)
  test/         mirrors lib/, one test file per source file it covers
```

## Architecture

**Layering:** `ui/` → `domain/` (services) → `data/` (Drift/SQLite). The UI never writes SQL
directly except for simple CRUD (metrics, templates); every rule about actions and their
dependencies lives in a domain service, so it's testable independently of any widget and so a
future sync layer doesn't have to re-derive it.

**Schema decisions**, and why:
- **No parent/child task hierarchy.** `action_dependencies` (predecessor/successor — "this must
  happen before that") is the *only* linking mechanism between actions. It's a graph, not a tree.
- **Every table's primary key is a text UUIDv7** (`core/ids.dart`), not an autoincrementing
  integer. Two offline devices creating rows independently can't collide on an ID, and UUIDv7 is
  time-ordered so indexes stay efficient. This is what makes a future PowerSync/Postgres sync
  layer a matter of adding a sync client, not a schema migration.
- **Every timestamp is UTC ISO-8601 text**, not Drift's native integer-based `DateTime` column
  (`core/time_codec.dart`), formatted at a fixed width so plain text ordering agrees with
  chronological order — this matters for the view queries' `ORDER BY`/range filters, and it keeps
  the on-disk format identical to what a Postgres sync target would expect.
- **Postponing an action moves that same row's time forward**; it doesn't create a new row. An
  `action_occurrences` log records each start/finish/postpone so a habit's history (and eventually
  a "how overdue is this life area" balance calculation) isn't lost to the overwrite.

**The two view queries with real logic** (`data/queries.dart`) are hand-written SQL using
recursive CTEs, not Drift's query builder:
- **TODO** — a task is ready to schedule once every one of its predecessors already has a
  start time (or it has none).
- **Most Important to Schedule** — ranks unscheduled, unblocked actions by their linked metrics'
  total weight, then by how many other actions are transitively downstream of finishing them
  (a single recursive CTE computes this for every action at once, not per-row).

**Cycle safety:** `domain/dependency_service.dart` rejects a new predecessor → successor edge if
the successor can already reach the predecessor going forward — i.e. adding it would close a loop.
This is also a recursive CTE, run once before the edge is inserted.

## Testing

Domain and query tests run against an in-memory Drift database
(`AppDatabase.forTesting(NativeDatabase.memory())`); the widget test overrides the database
provider the same way, so no test touches the real on-disk file.

One gotcha if you add a widget test that mounts a screen using a Drift stream: unmounting that
tree must be followed by a pump with a **non-zero** duration (e.g.
`tester.pump(const Duration(milliseconds: 1))`). Drift schedules a zero-duration timer when a
stream subscription is cancelled, and a duration-less pump doesn't advance fake time far enough
for that timer to fire before `flutter_test`'s pending-timer check runs.
