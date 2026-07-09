# Frontend — Personal Assistant Voice-to-Chores

This is the **Flutter mobile app** plus the **`supabase/` folder** (database schema,
storage config, and RLS policies). The app records audio, uploads it to Supabase
Storage, calls the Heroku backend, polls job status, and displays the generated
chores. All transcription and LLM work happens on the backend — the app never
talks to OpenAI.

---

## Responsibilities

```text
Record audio
Upload audio to Supabase Storage
Call the Heroku backend API
Poll job status
Display the generated chores
```

The `supabase/` folder additionally owns:

```text
Postgres schema (recordings + chores)
Storage bucket + path convention
RLS / storage access policies
```

---

## Stack

```text
Flutter mobile app
Supabase Storage   (raw audio recordings)
Supabase Postgres  (users, recordings, transcripts, chores, status)
Supabase Auth      (optional for MVP)
Heroku Web API     (backend orchestration — see backend CLAUDE.md)
```

Do **not** use Supabase Edge Functions for the MVP — Heroku already owns the
API logic, transcription orchestration, LLM prompt, and DB inserts. Edge
Functions also have duration limits that make long transcription risky.

---

## Full User Flow

```text
User taps record
→ app starts recording
→ user stops recording
→ app saves local audio file
→ app uploads audio to Supabase Storage
→ app calls POST /recordings with the audio_path
→ app receives job_id
→ app polls GET /recordings/:id until done or failed
→ app displays chores
```

For MVP, recording starts inside the app. Later this can be triggered from an
Android home-screen widget, Android Quick Settings tile, iOS Shortcut, or the
iOS Action Button / App Intent.

---

## 1. Recording

Recommended format and limits:

```text
Format: .m4a / .aac
Max duration: 90 seconds
Max file size: 10–20 MB
```

Keeping recordings short means faster upload, lower transcription cost, less
chance of a Heroku dyno restart mid-processing, and better UX — still plenty for
quick chore notes.

---

## 2. Upload to Supabase Storage

Upload the local audio file using a **user-specific path**:

```text
recordings/{user_id}/{recording_id}.m4a
```

Example:

```text
recordings/user_123/rec_456.m4a
```

After upload the app holds:

```text
audio_path = recordings/user_123/rec_456.m4a
```

For MVP, a direct authenticated Supabase upload is fine as long as the storage
policies are correct (see `supabase/` below). Alternatively the app can request a
signed upload URL from the backend.

---

## 3. Call the Backend

```http
POST /recordings
```

Request:

```json
{
  "audio_path": "recordings/user_123/rec_456.m4a"
}
```

Response (returned immediately — do **not** expect chores here):

```json
{
  "job_id": "rec_456"
}
```

The backend returns before transcription runs, so the app must poll.

---

## 4. Poll Job Status

```http
GET /recordings/:id
```

While processing:

```json
{
  "id": "rec_456",
  "status": "processing"
}
```

When done:

```json
{
  "id": "rec_456",
  "status": "done",
  "transcript": "I need to buy milk and call Avi tomorrow.",
  "chores": [
    { "title": "Buy milk", "due_date": null,         "priority": "normal", "notes": null },
    { "title": "Call Avi",  "due_date": "2026-07-09", "priority": "normal", "notes": null }
  ]
}
```

### Polling strategy

```text
Every 2 seconds for the first 20 seconds
Every 5 seconds after that
Stop after 2–3 minutes and show "Still processing"
```

### Statuses to surface in the UI

```text
Uploading...
Processing...
Creating chores...
Done
Failed, tap to retry
```

Backend status values: `uploaded`, `processing`, `done`, `failed`.

---

## 5. Retry

If a job comes back `failed`, let the user tap retry:

```http
POST /recordings/:id/retry
```

The backend resets status to `uploaded`, clears the error, and reprocesses.

---

## `supabase/` Folder

The Flutter repo owns the Supabase schema, storage, and policies. The backend
reads from and writes to these tables but does not define them.

### Schema — `recordings`

```sql
create table recordings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  audio_path text not null,
  status text not null default 'uploaded',
  transcript text,
  error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

Statuses:

```text
uploaded
processing
done
failed
```

### Schema — `chores`

```sql
create table chores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  recording_id uuid references recordings(id),
  title text not null,
  due_date date,
  priority text default 'normal',
  notes text,
  is_done boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

### Storage

```text
Bucket:          recordings
Path convention: recordings/{user_id}/{recording_id}.m4a
```

### Security / RLS

```text
Use user-specific storage paths.
Do not let users read or write other users' recordings.
Storage + row policies must scope every read/write to the authenticated user_id.
```

The backend independently re-validates that `audio_path` belongs to the current
user, but the RLS policies here are the first line of defense.

---

## Later Additions (Not for MVP)

```text
Android widget / Quick Settings tile
iOS Shortcut / Action Button / App Intent
Push notifications when chores are ready
Recurring chores
Calendar integration
Paid tiers with longer recording limits
```
