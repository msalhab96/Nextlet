# Nextlet guide

Everything beyond the [quick start](../README.md#quick-start).

Nextlet has three parts that share one server:

- a **web app** (React) that runs in Docker alongside the API and database, when you want it,
- a **native macOS app** (SwiftUI) with a menu bar extra, ⌥Space quick capture,
  a floating focus timer, and light and dark appearances,
- a **REST API** (Node.js + PostgreSQL) that both apps talk to.

## What you can do

- **Today**: a *Next up* card for the one thing to do now, your list for the day
  (drag to reorder, or "Make next up"), what you've done, and what you moved to tomorrow.
- **Move to tomorrow**: on every task, on the Next up card, in the details panel,
  or for the whole list at once ("Move unfinished to tomorrow"). Every move can be
  undone. Unfinished tasks from earlier days show up on Today marked "From Tue".
- **Upcoming**: a week view where you push a task to the next day or drag it onto
  any day, plus a month calendar.
- **Inbox** for tasks without a day, and **projects** with their own colours.
- **Quick add** understands plain language: `Call mom tomorrow #Personal !2`.
- **Focus** sessions: a countdown for the task in front of you with its next step,
  "Start next" when you're done, and short breaks.
- Subtasks, notes, estimates, priorities and repeating tasks (daily, weekdays,
  chosen weekdays, every _n_ days, monthly), search across titles and notes, and
  optional password protection.

## 1. Run the server and web app (Docker)

Requirements: Docker with Compose v2 (Docker Desktop, or Colima with the Docker CLI).

```bash
cp .env.example .env                          # optional: database password, ports, password protection…
docker compose up -d --build                  # the server: API on :8080 (what the Mac app uses) and the database
docker compose --profile web up -d --build    # …and the web app on http://localhost:8081
```

The web app only runs when you ask for it with `--profile web`; the Mac app needs just
the server. To start with a week of sample tasks, set `SEED_DEMO=true` in `.env` before
the first start (it only loads into an empty database).

```bash
docker compose logs -f api                # follow the API logs
docker compose --profile web stop web     # stop just the web app
docker compose --profile web down         # stop everything (your data stays in the db-data volume)
docker compose --profile web down -v      # stop and delete all data
```

| Service | Image                | What it does                                                                      |
| ------- | -------------------- | --------------------------------------------------------------------------------- |
| `api`   | built from `server/` | Node.js + Fastify REST API on port 8080. Runs database migrations on start.        |
| `db`    | `postgres:17-alpine` | PostgreSQL, data in the `db-data` volume.                                          |
| `web`   | built from `web/`    | Only with `--profile web`: nginx serving the React app on port 8081, proxying `/api` to the API. |

### Starting after a restart

The containers restart on their own whenever Docker starts (the web app too, if it
was running). With Colima, make Docker start at login once:

```bash
brew services start colima   # brew services stop colima to undo
```

Docker Desktop has the same option in its settings ("Start Docker Desktop when you
sign in"). The Mac app opens at login too (Settings › General › Startup) and keeps
retrying until the server is up.

## 2. The Mac app

Requirements: macOS 15 or later and the Xcode Command Line Tools
(`xcode-select --install`). Full Xcode works too but isn't needed.

```bash
cd mac
./scripts/build-app.sh          # builds mac/build/Nextlet.app
open build/Nextlet.app          # or drag it into /Applications
```

The app connects to `http://localhost:8080`, the Docker setup above. Point it
elsewhere in **Nextlet › Settings › Server**. If the server has a password, the
app asks for it once and keeps a session (not the password).

What's in it:

- **Main window**: sidebar with Inbox, Today, Upcoming, Focus and your projects;
  the task list with the Next up card; and a details panel (drag its left edge to
  resize it). Drag tasks onto sidebar items to reschedule them or change their
  project. Right-click any task for everything you can do with it.
- **New task** (**+** in the toolbar or **⌘N**): opens quick capture filed under the
  screen you're on, so a task added inside a project lands in that project.
- **Menu bar extra**: today's next task (or the running focus clock) in the menu
  bar. Click it to start focus, complete, push to tomorrow and add tasks without
  opening the window.
- **Quick capture**: press **⌥Space** in any app, type `Call mom tomorrow #Personal !2`,
  press Return. Change the shortcut in Settings › Shortcuts.
- **Floating focus timer**: a small always-on-top timer with pause, +5 min, Done
  and the current step. Pin or unpin it, or hide it and keep the clock in the menu bar.
- **Light and dark**: follows your Mac by default. Choose Light or Dark in
  Settings › General or from View › Appearance.

Closing the window keeps Nextlet in the menu bar. Quit from the menu bar's power
button or with ⌘Q. The build is signed ad hoc, which is fine on your own Mac. To
share the app, sign it with a Developer ID and notarize it.

## Password protection

Set `NEXTLET_PASSWORD` in `.env` and restart (`docker compose up -d`). The web app
then shows a sign-in screen, and the Mac app asks for the password in its window.
Sessions last 30 days. The lock button in the sidebar signs you out. Changing the
password signs everyone out. Ten wrong attempts lock sign-in for five minutes.

Nextlet only listens on `127.0.0.1` by default. To use it from other devices
(for example the Mac app on another computer), set a password first, then set
`NEXTLET_BIND=0.0.0.0`. Put it behind HTTPS (a reverse proxy) if it leaves your home network.

## Configuration (`.env`)

| Variable            | Default     | Meaning                                                                  |
| ------------------- | ----------- | ------------------------------------------------------------------------ |
| `POSTGRES_PASSWORD` | `nextlet`   | Database password. Letters, digits, `-` and `_` only (it goes in a URL). |
| `NEXTLET_PORT`      | `8080`      | Port of the server (the Mac app connects here).                          |
| `NEXTLET_WEB_PORT`  | `8081`      | Port of the web app, when it runs (`--profile web`).                     |
| `NEXTLET_BIND`      | `127.0.0.1` | Interface to listen on. `0.0.0.0` makes it reachable from your network.  |
| `NEXTLET_PASSWORD`  | empty       | Require this password in both apps. Empty means no sign-in.              |
| `SESSION_SECRET`    | empty       | Optional extra secret mixed into session signatures.                    |
| `SEED_DEMO`         | `false`     | Load sample tasks into an empty database on first start.                 |
| `LOG_LEVEL`         | `info`      | API log level (`debug`, `info`, `warn`, `error`).                        |

## Using Nextlet

### Quick add

Works in every "New task" field, in the web app's quick capture (**N**) and the Mac app's (**+**, **⌘N** or **⌥Space**).

| You type                                  | Nextlet understands                                |
| ----------------------------------------- | -------------------------------------------------- |
| `today`, `tomorrow`, `tmrw`               | that day                                           |
| `friday`, `on fri`, `… fri` (at the end)  | the next Friday (never today)                      |
| `next week`, `next mon`                   | next Monday / Monday of next week                  |
| `in 3 days`, `in 2 weeks`                 | relative days                                      |
| `5 oct`, `oct 5th`, `2026-10-05`          | that date                                          |
| `someday`                                 | no day; it goes to the Inbox                       |
| `#Personal`, `#side-project`              | the project (a new one is created if needed)       |
| `!1`, `!2`, `!3`                          | priority high / medium / low                       |

Short weekday names only count after "on" or at the end, so "Buy sun cream"
stays a title. Times like "6pm" are left in the title: tasks have days, not hours.

### Keyboard shortcuts

| Web app         | Mac app       | Action                                         |
| --------------- | ------------- | ---------------------------------------------- |
| ⌘K / Ctrl K     | ⌘K            | Search tasks and notes (including done ones)   |
| N               | ⌘N            | New task (quick capture; on the Mac, filed under the screen you're on) |
| —               | ⌥Space        | Quick capture from any app                     |
| F               | ⌘F            | Start focus on the selected (or next) task     |
| ⌘↵ / Ctrl ↵     | ⌘↵            | Complete the selected task                     |
| ⌘→ / Ctrl →     | ⌘→            | Move the selected task to the next day         |
| ⌘Z / Ctrl Z     | ⌘Z            | Undo the last move, completion or delete       |
| —               | ↑ ↓           | Select the previous or next task               |
| —               | ⌘⌫            | Delete the selected task                       |
| T / I / U       | ⌘1 – ⌘4       | Go to Today / Inbox / Upcoming (/ Focus)       |
| Esc             | Esc           | Close the details panel / deselect             |
| ?               | ⌘/            | Show all shortcuts                             |

## How it fits together

```
browser ──▶ web (nginx, :8081) ──/api──▶ api (Fastify, :8080) ──▶ db (PostgreSQL)
Mac app ─────────────────────────/api──┘
```

- **`server/`**: Fastify 5, `pg` and Zod. SQL migrations in `server/migrations` run
  automatically at startup. `src/auth.ts` holds the optional password protection
  (signed session tokens, sent as a cookie by the web app and a Bearer header by the Mac app).
- **`web/`**: React 19, TypeScript and Vite. One small store (`src/store/store.ts`)
  applies every change instantly and rolls it back if the API refuses it. Fonts
  are bundled, so the app makes no third-party requests, and nginx sets a strict
  Content-Security-Policy.
- **`mac/`**: a Swift package. `NextletCore` holds the shared rules (days, quick
  add, where tasks show up), mirroring `web/src/lib`. `Nextlet` is the SwiftUI app,
  and its `Store` is a port of the web store.

### The day model

| Column         | Meaning                                                                         |
| -------------- | ------------------------------------------------------------------------------- |
| `day`          | The day a task is planned for (`NULL` = Inbox). Once done, the day it was done. |
| `planned_day`  | Where it was last deliberately scheduled. Pushing a task leaves this alone, which is how "From Tue" works. |
| `postponed_at` | Set when a task is pushed forward; powers "Moved to tomorrow" on Today.         |

Open tasks dated before today appear on Today. Completing a repeating task
creates the next occurrence; undoing the completion removes it again.

### API

All endpoints are under `/api` and speak JSON. Days are `YYYY-MM-DD` strings.

| Method & path                    | Purpose                                                        |
| -------------------------------- | -------------------------------------------------------------- |
| `GET /health`                    | Liveness and database check                                    |
| `GET /auth/status`               | `{ required, authenticated }`                                  |
| `POST /auth/login`               | `{ password }`: sets the session cookie and returns a token   |
| `POST /auth/logout`              | Clears the session cookie                                      |
| `GET /projects`                  | List projects                                                  |
| `POST /projects`                 | Create `{ name, color? }`                                      |
| `PATCH /projects/:id`            | Update `{ name?, color?, sortOrder? }`                         |
| `DELETE /projects/:id`           | Delete; its tasks are kept without a project                   |
| `GET /tasks?status=open`         | Every open task                                                |
| `GET /tasks?status=done&from&to` | Done tasks between two days                                    |
| `GET /tasks?q=…`                 | Search titles and notes                                        |
| `POST /tasks`                    | Create `{ title, day?, projectId?, estimateMinutes?, priority?, repeat?, notes?, subtasks? }` |
| `PATCH /tasks/:id`               | Update any of those; setting `day` reschedules the task        |
| `DELETE /tasks/:id`              | Delete                                                         |
| `POST /tasks/:id/complete`       | Complete `{ today }`; returns the next occurrence if it repeats |
| `POST /tasks/:id/uncomplete`     | Reopen                                                         |
| `POST /tasks/move`               | `{ moves: [{ id, day }], postponed }`, e.g. move to tomorrow   |
| `POST /tasks/reorder`            | `{ ids }` in their new order                                   |
| `POST /tasks/:id/subtasks`       | Add a subtask `{ title }`                                      |
| `PATCH /subtasks/:id`            | `{ title?, done? }`                                            |
| `DELETE /subtasks/:id`           | Delete a subtask                                               |

When `NEXTLET_PASSWORD` is set, everything except `/health` and `/auth/*` needs the
session cookie or an `Authorization: Bearer <token>` header.

## Developing

Requirements: Node.js 22+ and a PostgreSQL you can reach (for example
`docker compose up -d db` with `ports: ["5432:5432"]` added to the `db` service).

```bash
# API on :3000
cd server && npm install
DATABASE_URL=postgres://nextlet:nextlet@localhost:5432/nextlet SEED_DEMO=true npm run dev

# Web app on :5173 (proxies /api to :3000)
cd web && npm install && npm run dev

# Mac app against the dev API: set Settings › Server to http://localhost:3000
cd mac && ./scripts/build-app.sh debug && open build/Nextlet.app
```

### Tests

```bash
cd server && npm test                      # dates, repeats, auth
cd server && TEST_DATABASE_URL=postgres://nextlet:nextlet@localhost:5432/nextlet npm test
                                           # + API tests in a throwaway schema
cd web && npm test                         # quick-add parser, dates, task rules
cd mac && ./scripts/test.sh                # NextletCore: same parser and rules in Swift

# The Mac app can check itself against a running server. It uses its own
# settings and only touches tasks and projects it creates (then removes them):
mac/build/Nextlet.app/Contents/MacOS/Nextlet --self-test http://localhost:8080 [--password …]
# …click and type through its real window (off screen) and check that every
# dropdown, field and button works and that the server saves the changes:
mac/build/Nextlet.app/Contents/MacOS/Nextlet --ui-test http://localhost:8080
# …and render its screens to PNG files without opening any window (--dark for dark mode):
mac/build/Nextlet.app/Contents/MacOS/Nextlet --snapshot ~/Desktop/nextlet-shots http://localhost:8080 [--dark]
```

`npm run typecheck` and `npm run build` work in `server/` and `web/`.

## Backups

```bash
docker compose exec db pg_dump -U nextlet nextlet > nextlet-backup.sql
docker compose exec -T db psql -U nextlet nextlet < nextlet-backup.sql   # restore into an empty database
```
