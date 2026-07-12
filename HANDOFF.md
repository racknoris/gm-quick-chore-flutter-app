# GM Quick Chore — Handoff

Voice-to-chores app: record audio → transcribe → LLM extracts chores → display.
Two repos: **Flutter app + `supabase/`** (this repo) and **`gm-quick-chore-backend`**
(Node/TS on Heroku). All secrets live in `.env` / `key.properties` (gitignored).

> **Hard rule:** never read/inspect `.env` files — only `.env.example`. Secrets
> are managed by the owner.

---

## Architecture

```
Flutter app (il.co.getmarketing.quickchore)
  ├─ Supabase Auth  (JWT; MANDATORY on every backend call)
  ├─ Cloudflare R2  (audio blobs, via presigned PUT URL from backend)
  └─ Heroku backend (Node/TS) ── OpenAI (transcribe + extract)
                              └─ Supabase Postgres (recordings + chores)
```

- **Supabase = Auth + Postgres only** (NOT storage — audio is in R2).
- **Backend** does all DB access via `supabase-js` (through the Data API/PostgREST)
  + service-role for background work.
- Schema/migrations live in **this repo** (`supabase/`); run the Supabase CLI from
  here (or `--workdir ../gm_quick_chore_flutter_app`).

---

## What's built (all working, verified locally + on-device)

**Backend** (`gm-quick-chore-backend`, Node 24.14.0, TypeScript → `dist/`):
- Endpoints: `POST /recordings/upload-url` (presigned R2), `POST /recordings`,
  `GET /recordings`, `GET /recordings/:id`, `DELETE /recordings/:id`,
  `POST /recordings/:id/retry`, `PATCH /chores/:id`, `DELETE /chores/:id`, `/health`.
- Real OpenAI pipeline: download from R2 → `gpt-4o-transcribe` → extraction →
  insert. **Idempotent**; stuck jobs recovered on boot + every 5 min (Postgres-as-
  queue, web-dyno-only — no worker yet).
- Auth middleware verifies Supabase JWT; derives `user_id` (never from body).
- e2e suite: `npm run test:e2e` (22 checks, hits real Supabase + R2 + OpenAI).
  See `TESTING.md` and `.claude/skills/verify/SKILL.md`.

**Flutter app** (flutter_bloc, supabase_flutter):
- Auth gate that waits for a **valid** token before showing the app (no 401 flash).
- Record → upload (presigned R2 PUT) → poll → display; history list; chore
  toggle/edit/delete; recording delete (swipe + detail action).
- **Background recording** via `flutter_foreground_task`: recorder runs in the
  service isolate (`lib/services/background_recorder.dart`), survives screen-off /
  backgrounding, persistent "GM Quick Chore — Recording…" notification with Stop.
  Verified on Android device (backgrounded, screen off, app-stop, notification-stop).
- Audio: AAC-LC, 64 kbps, 16 kHz mono, Android VOICE_RECOGNITION. Max 30 min / 25 MB.

**Schema** (`supabase/migrations/…_init_schema.sql`): `recordings` + `chores`,
RLS owner-scoped policies, **grants to authenticated + service_role** (RLS alone
isn't enough), `updated_at` triggers, `chores.position numeric` (fractional order).
v2-nullable: `due_date`/`priority`/`notes`/`recorded_at`.

---

## Environments & config

Compile-time `ENV` define selects config (`lib/config.dart`), no runtime `.env`:

| ENV | Host | Use |
|---|---|---|
| `localSimulatorIOS` (default) | 127.0.0.1 | iOS sim / macOS / web |
| `localEmulatorAndroid` | 10.0.2.2 | Android emulator |
| `localDevice` | LAN IP (e.g. 10.0.0.6) | physical device |
| `staging` / `prod` | hosted URLs | deployed |

- VS Code: `.vscode/launch.json` has one F5 config per env.
- `staging` and `prod` are currently **identical** (single shared env, by design).
- Only publishable/anon values in `config.dart` — real secrets stay server-side.

---

## Deploy state (in progress)

- **Backend:** deployed to Heroku app `gm-quick-chore`
  (`gm-quick-chore-d393b31d5d51.herokuapp.com`). Deploy via `prod` branch pointer
  (`git push prod prod:main`); config vars set from `.env.production` (dotenv-cli).
- **Supabase:** remote project created; migration pushed (a non-fatal `pgdelta`
  cert warning appeared — push still succeeded).
- **Release signing (Android):** `android/key.properties` + keystore configured;
  `build.gradle.kts` uses release signing (falls back to debug if key.properties
  absent). Package renamed everywhere to `il.co.getmarketing.quickchore`.
- Build APK: `flutter build apk --release --dart-define=ENV=prod`
  (→ `build/app/outputs/flutter-apk/app-release.apk`; share via Drive, sideload).

---

## Resolved: Supabase Data API

Earlier the remote app returned `PGRST002` / "Something went wrong" after login
because the Supabase **Data API (PostgREST) was disabled** (the backend accesses
the DB through it via `supabase-js`). **Now re-enabled** — resolved. Safe, since
RLS + grants scope every row to `auth.uid()`.

Optional future hardening: since only the backend touches the DB (the app goes
through the backend + R2, and uses Supabase only for Auth), you *could* keep the
Data API off and switch the backend to a **direct Postgres connection** (`pg`
driver). Bigger surface reduction, but a real refactor — not needed now.

---

## Other open items

- **Email confirmation** redirects to `localhost:3000` (default Site URL). Simplest
  for MVP: disable "Confirm email" in Supabase Auth. Otherwise set a deep-link Site
  URL and handle it in-app.
- **iOS** background recording not yet tested on device (config is in place:
  `UIBackgroundModes: audio`); iOS bundle id renamed. Real iPhone over `http://`
  needs an ATS cleartext exception (Android already handled in debug/profile).
- **Pause recording** (deferred): `record` supports pause/resume; needs main→handler
  messaging + a `paused` state. Then layer **auto-pause on call interruption** (via
  the recorder's state stream — don't detect calls directly).
- `flutter_foreground_task` triggers a **KGP deprecation warning** (harmless now;
  future Flutter will require the plugin to migrate to Built-in Kotlin).
- **Worker + queue**: only needed when multiple users hit long jobs concurrently.
  Single-user is fine on web-dyno-only.
- **R2 CORS**: only needed if you ship Flutter **Web** (native ignores CORS).
- Backend `.env` limit vars (`MAX_AUDIO_*`) kept as-is; not secrets.
- Note: `OPENAI_EXTRACTION_MODEL` is set to `gpt-5.5-2026-04-23` in `.env`
  (the docs' `gpt-5.5-mini` was a placeholder / not real; code default is
  `gpt-4o-mini`, overridable via env).

---

## Conventions

- Branch: develop on `main`; `prod` is a **deploy pointer** (merge main → prod →
  push). Tag releases (`v1.0`) — never tie environment to branch (config does that).
- Node backend: prefix commands with `nvm use 24.14.0`.
- Keystore: reuse the **same** key for every update; keep it safe; never commit.
