# LiveNow

A personal task-management app (GTD-style): actions chained by previous/next dependencies, a
calendar, planning, a budget, and "growth directions" that measure whether your actions keep the
important areas of life in balance. It replaces a Notion prototype with a fast, reliable,
offline-first app.

**Status:** Windows desktop is the main target. An iPhone client (phone layout, sync client), an
always-on sync hub and a macOS port (unsigned, not yet verified on a real Mac) exist. Developer
notes live in `CLAUDE.md` (kept locally, not in git) and `dev/NOTES.md` (round-by-round history).

## Features

- **Actions** (one section, switchable views)
  - **Current** — a Done Before / Not Done Yet board with a hover toolbar (Start, Finish, Continue,
    postpone, delete), marquee and Ctrl/Shift multi-select, search, and paging for large lists.
  - **Calendar** — time grid with a 1–7 day range, drag to move, resize across days, drag on empty
    space to create, rubber-band select, group move/delete, zoom, all-day strip, plan ghosts.
  - **All** — every action in one list: search by name, notes and growth directions, multi-field
    sort, filters, bulk edit. Without a chosen sort, whole-word matches come first.
  - **Templates** and **Forms** — reusable actions, and questionnaires whose answers add growth
    directions (and optionally a Countable Activity) to selected actions.
  - **CSV import** of Notion exports (actions, templates, directions, budget).
- **Action editor** — name, quick buttons (Start, Finish, postpone, delete…), start/end with
  duration and All day, urgency, growth directions, a rich **Notes** editor (checkboxes, links),
  previous/next actions, and a new action gets the same menu. Related things open from every edit
  menu. Undo (toast or Ctrl+Z) for destructive and state-changing operations.
- **Growth directions** — Balance boards, Treemap (area = time spent or planned hours), List and
  Mindmap; each direction has a target over a rolling window and a computed urgency.
- **Planning mode** — cycles and monthly rules generate ghost actions; confirm them (all/none) into
  real actions, edit templates from the plan editor.
- **Budget** — categories (tree, plan vs fact), accounts with rates, transactions, JSON backup and
  Notion CSV import.
- **Search** — `Ctrl+F` focuses the search of the view you are on; `Ctrl+K` opens one window over
  actions, templates, directions, categories, transactions, forms and plan items with section chips
  and an "Updated" filter (Cmd instead of Ctrl on a Mac). Notes keep `Ctrl+K` as the link command.
- **Accounts, sync, backup** — several local accounts per device (optional password and TOTP 2FA,
  idle lock after 30 minutes by default for accounts with a password), encrypted peer-to-peer sync
  with a hub (`livenow.exe --hub`), `.livenow` full backups and automatic backups.
- Light and dark glass look, phone layout for narrow windows, reminders, Istanbul wall-clock time
  for all scheduling rules.

## Tech stack

| | |
|---|---|
| App | [Flutter](https://flutter.dev) (Dart): Windows, iOS, macOS |
| Local database | SQLite via [Drift](https://drift.simonbinder.eu) |
| State management | [flutter_riverpod](https://riverpod.dev) |
| Sync | own engine (hybrid logical clock, last writer wins per row, AES-256-GCM over HTTP, port 47653) |
| Notes editor | [appflowy_editor](https://pub.dev/packages/appflowy_editor), pinned to a git commit |

## Getting started

1. Install the [Flutter SDK](https://docs.flutter.dev/get-started/install/windows/desktop) and
   add its `bin/` folder to `PATH`.
2. Install **Visual Studio 2022** with the **"Desktop development with C++"** workload.
3. Enable **Windows Developer Mode** (Settings → Privacy & security → For developers) — Flutter
   needs symlinks for plugin packages.
4. From `app/`:
   ```
   flutter pub get
   dart run build_runner build   # generates lib/data/database.g.dart from tables.dart
   flutter run -d windows
   ```

If `flutter`/`dart` aren't recognized in a fresh shell, reload `PATH` in PowerShell:
```powershell
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
```

macOS, iOS, Android and a portable Windows zip are built in GitHub Actions on a tag
(`mac-*`, `ios-*`, `android-*`, `win-*`); the result is a 7-day workflow artifact.

## Installing the builds

- **Windows (portable):** unzip `LiveNow-windows-x64.zip` anywhere and run `livenow.exe` (the
  Visual C++ runtime DLLs are inside). SmartScreen may warn because the app is unsigned: More
  info → Run anyway. Locally: `flutter build windows --release`, then
  `app/windows/package/pack_windows.ps1` makes the zip.
- **Android:** download `livenow.apk` from the `android-*` workflow run, copy it to the phone (or
  `adb install livenow.apk`) and allow "install unknown apps". It is signed with the project's
  release key (GitHub secrets `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`; the local copy of the key is not in git: keep a
  backup, a lost key means the next build cannot update an installed app). Android is a phone
  client: it syncs with a PC or hub (plain HTTP on the LAN/VPN inside AES envelopes, so cleartext
  traffic is enabled), shows reminders through the system, pairs by QR (camera). Not yet verified
  on a real phone.
- **macOS / iOS:** see the notes in `dev/NOTES.md` (unsigned `.dmg`, sideloaded `.ipa`).

## Commands

All run from `app/`:

```
flutter pub get                          # install dependencies
dart run build_runner build              # regenerate lib/data/database.g.dart after editing tables.dart
flutter analyze                          # static analysis
flutter test                             # run all tests (heavy: prefer single files)
flutter test test/domain/some_test.dart  # run a single test file
flutter run -d windows                   # run the app
flutter build windows --release          # release build
```

## Project structure

```
app/
  lib/
    core/       shared helpers: UUIDv7 ids, UTC<->text timestamps, settings, text/number rules,
                capped file reads, DB error mapping, error log
    data/       Drift schema + migrations, queries, accounts, backup, sync, reminders
    domain/     business rules and services: actions, dependencies, growth, budget, plans, forms,
                search ranking, sync merge, CSV import
    hub/        the headless sync hub (livenow.exe --hub)
    ui/         providers, glass theme, widgets, views (Current, Calendar, All), screens
  test/         mirrors lib/
  macos/        macOS runner and hub install script
dev/            Notion-prototype spec (Actions-Template-Function-Reference.md), notes, sample data
```

## Architecture

**Layering:** `ui/` → `domain/` (services and pure rules) → `data/` (Drift/SQLite). The UI never
writes SQL except simple CRUD; rules live in domain services so they are testable without widgets
and sync does not have to re-derive them.

**Schema decisions** (schema version 17):
- **No parent/child hierarchy.** `action_dependencies` (predecessor/successor) is the only link
  between actions: a graph that must stay acyclic.
- **Every primary key is a text UUIDv7**, so offline devices cannot collide and sync needs no
  migration.
- **Every timestamp is fixed-width UTC ISO-8601 text**, so text order is chronological order.
- **Postponing moves the same row's time**; there is one action type, distinguished by `is_all_day`.
- **"Done" is derived** (`domain/done_rule.dart`, SQL twin in `data/queries.dart`); `actions.done` is
  only a manual flag.
- **Growth directions** (`metrics`): boolean, count or hours over a rolling window against a
  target; progress, urgency and weight come from `domain/growth_rules.dart`.
- **Sync** is tracked by SQL triggers and per-row clock stamps; deletions are tombstones; the wire
  version must match on both sides.

**Performance first:** the glass look is drawn from one pre-rendered background with cheap
per-surface draws (no per-surface blur), list queries filter and page in SQL, sections are kept
alive, and the calendar and mindmap build only what is visible.

## Importing from CSV

Use the upload buttons in the Actions, Templates, Growth directions and Settings screens with a
Notion export. For actions the columns are
`Name, Datetime, Next actions and time, Previous actions and time, Growth Direction`; dates are
day-first (`DD/MM/YYYY`; a date alone makes an all-day action). A summary lists what was created or
skipped. Importers refuse oversized or damaged files and say "Nothing was changed."

## Testing

Domain and query tests run against an in-memory Drift database
(`AppDatabase.forTesting(NativeDatabase.memory())`); widget tests override the database provider,
so no test touches the real on-disk file. Beyond unit tests there are stress and edge-case suites
(`calendar_stress_test`, `device_edge_test`, `*_edge_test`, account isolation, sync failure).

Gotchas: after unmounting a tree that uses a Drift stream, pump a **non-zero** duration
(`tester.pump(const Duration(milliseconds: 1))`); seed the database before mounting; the default
test surface (800x600) is the phone layout. More traps are listed in `CLAUDE.md`.

## Data and manual UI checks

App data (SQLite file per account, settings) lives in `%APPDATA%\io.livenow\livenow\`. The schema
migrates forward on start and cannot be rolled back, so copy that folder before installing a build
with a newer schema.

When driving the app by script, **never run it against your real data**: start it with
`LIVENOW_DATA_DIR=<empty folder>` so every click lands on a throwaway database.
