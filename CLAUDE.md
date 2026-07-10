# Frontend — Personal Assistant Voice-to-Chores

This is the **Flutter mobile app** plus the **`supabase/` folder** (database schema
and RLS policies). The app records audio, uploads it to **Cloudflare R2** via a
presigned URL from the backend, calls the Heroku backend, polls job status, and
displays the generated chores. All transcription and LLM work happens on the
backend — the app never talks to OpenAI, and never holds R2 credentials.

---

## Responsibilities

```text
Record audio
Upload audio to Cloudflare R2 (via presigned URL from the backend)
Call the Heroku backend API
Poll job status
Display the generated chores
```

The `supabase/` folder additionally owns:

```text
Postgres schema (recordings + chores)
RLS / row access policies
```

Audio storage is **Cloudflare R2** (owned by the backend), not Supabase Storage.

---

## Stack

```text
Flutter mobile app
Cloudflare R2      (raw audio recordings — via backend presigned URLs)
Supabase Postgres  (users, recordings, transcripts, chores, status)
Supabase Auth      (MANDATORY — every backend call carries a Supabase JWT)
Heroku Web API     (backend orchestration — see backend CLAUDE.md)
```

Supabase Auth is **required**, not optional. Every request to the backend carries
the authenticated user's Supabase JWT in `Authorization: Bearer <token>`, and the
backend derives `user_id` from it. The client never sends `user_id` in a body.

Do **not** use Supabase Edge Functions for the MVP — Heroku already owns the
API logic, transcription orchestration, LLM prompt, and DB inserts. Edge
Functions also have duration limits that make long transcription risky.

### Dependencies

Use the **latest** packages, with these minimum pins:

```text
flutter_bloc:     ^9.1.1   (state management — use BLoC/Cubit throughout)
supabase_flutter: ^2.16.0  (auth + storage upload + Postgres access)
```

State management is **flutter_bloc**. Model the record → upload → poll → display
flow as a Cubit/BLoC with explicit states that map to the UI statuses below.

---

## Full User Flow

```text
User taps record
→ app starts recording
→ user stops recording
→ app saves local audio file
→ app gets a presigned URL (POST /recordings/upload-url) and PUTs audio to R2
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
Format:       .m4a / .aac (AAC-LC)
Encoding:     64 kbps, 16 kHz, mono   (speech-tuned; Android uses VOICE_RECOGNITION)
Max duration: 30 minutes
Max file size: 25 MB
```

16 kHz mono matches what `gpt-4o-transcribe` uses internally, so higher settings
are wasted bytes. At 64 kbps, 30 min ≈ 14 MB — comfortably under OpenAI's 25 MB
transcription limit (~50 min is where you'd approach it). Long recordings make
transcription take minutes, so processing must not run on the web dyno alone —
see the backend's worker+queue note.

---

## 2. Upload to Cloudflare R2 (presigned URL)

Audio blobs live in **Cloudflare R2**, not Supabase Storage. The app never holds
R2 credentials — it uploads via a short-lived presigned URL from the backend:

```text
1. POST /recordings/upload-url  → { upload_url, audio_path, content_type }
2. PUT the audio bytes to upload_url  (Content-Type must match content_type)
3. audio_path (= {user_id}/{recording_id}.m4a) is the R2 key
```

Example:

```text
audio_path = user_123/rec_456.m4a
```

The presigned URL is scoped to the caller's folder, so a client can only write
its own path. The backend re-validates ownership on `POST /recordings`.

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
  "title": "Errands",
  "status": "done",
  "transcript": "I need to buy milk and call Avi tomorrow.",
  "created_at": "2026-07-09T12:00:00Z",
  "chores": [
    { "id": "chore_1", "content": "Buy milk", "is_done": false, "position": 1,
      "due_date": null, "priority": null, "notes": null },
    { "id": "chore_2", "content": "Call Avi", "is_done": false, "position": 2,
      "due_date": null, "priority": null, "notes": null }
  ]
}
```

Each recording carries an LLM-generated `title`, its recording date
(`created_at`), and a `chores` array. A recording that turns out to be a single
note is just a `chores` array of length 1 — the client always renders one list.
`due_date`, `priority`, and `notes` are **v2** and always `null` in the MVP.

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

### Empty vs failed

- A valid transcript with **no chores** is still a success: `status: done`,
  `chores: []`, and a `title` is still generated. Show an empty list, not an error.
- If the audio produced **no usable transcript**, the job comes back `failed` with
  a machine `error` code. Map the code to a clear message for the user:

```text
transcription_failed          → "Couldn't understand the recording. Try again."
network_error / openai_unavailable → "Connection problem. Tap to retry."
internal_error                → "Something went wrong. Tap to retry."
```

Always tell the user *what* happened; never show a raw error string.

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
  title text,                         -- LLM-generated; set when status = done
  transcript text,
  error text,                         -- machine error code when failed
  created_at timestamptz not null default now(),  -- treated as the recording date
  updated_at timestamptz not null default now(),

  -- v2 (nullable, unused in MVP):
  recorded_at timestamptz             -- client-supplied true record-start time
);
```

`created_at` is the recording date for the MVP (record → upload → POST happens
within seconds). A precise client-captured `recorded_at` is **v2**.

Statuses:

```text
uploaded
processing
done
failed
```

### Schema — `chores`

A chore holds a single `content` string (a chore *or* a note — same shape).
Ordering uses a **fractional `numeric` `position`**: insert between two rows with
`(prev + next) / 2`, append with `max(position) + 1`. `numeric` (not float) keeps
arbitrary precision so repeated inserts in the same gap never collide.

```sql
create table chores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  recording_id uuid references recordings(id),
  content text not null,              -- the chore/note text
  is_done boolean not null default false,
  position numeric,                   -- fractional ordering; order by position
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- v2 (nullable, unused in MVP — LLM leaves these null):
  due_date date,
  priority text,                      -- low | normal | high
  notes text
);
```

### Storage (Cloudflare R2, owned by the backend)

Audio is stored in R2, not Supabase Storage. The backend mints presigned upload
URLs and enforces ownership; the app never holds R2 credentials.

```text
Bucket:          R2 (private)  — see backend config
Key convention:  {user_id}/{recording_id}.m4a
```

### Security / RLS

```text
Row policies (recordings + chores) scope every read/write to auth.uid().
Audio access is controlled by short-lived presigned R2 URLs (backend-minted),
  each scoped to {user_id}/... so a client can only touch its own audio.
```

RLS on the tables is the first line of defense for data; the backend re-validates
that `audio_path` belongs to the current user on every request.

---

## 6. Chore actions

The chores list screen supports, in the MVP:

```http
PATCH  /chores/:id      → toggle is_done, edit content
DELETE /chores/:id      → remove a chore
```

Editing text and toggling done share `PATCH /chores/:id`. Deleting is allowed in
MVP. **Reorder** (drag to change `position`) is v2 — the `position` column exists
now so it drops in without a migration.

---

## 7. History list

A screen shows the user's past recordings:

```http
GET /recordings
```

Returns an array of recordings (each with `title`, `created_at`, `status`, and
`chores`). Pagination is **v2**.

Swipe a recording (or use the detail-screen delete action) to remove it:

```http
DELETE /recordings/:id      → deletes the recording, its chores, and its audio
```

Deletion is confirmed with a dialog; the list updates optimistically.

---

## v2 (deferred — schema/API already leaves room)

```text
Chore due_date / priority / notes   (nullable now; LLM fills later)
Chore kind: "chore" | "note"        (style single notes differently)
Chore reorder (drag → position)     (numeric position column exists now)
Client-supplied recorded_at         (nullable column exists now)
GET /recordings pagination
Android widget / Quick Settings tile
iOS Shortcut / Action Button / App Intent
Push notifications when chores are ready
Recurring chores
Calendar integration
Paid tiers with longer recording limits
```
