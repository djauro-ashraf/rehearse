# Rehearse

**Loop, slow down and master any audio.**
A practice player for anyone who learns by repetition: language learners,
musicians, memorisers (Quran, poetry, speeches), dancers, actors.

Import a recording → mark the passage you want → slow it down → repeat it until
it sticks. Everything you build (loops, markers, routines) is remembered, and
the app reopens exactly where you left off.

## What it does

| | |
|---|---|
| **A–B loop** | Drag handles on the timeline, tap *Set here*, nudge by 0.1 s (hold to speed up), or type an exact time. Zoom to the loop; lock the handles so a stray touch can't move them. Minimum loop 0.1 s. |
| **Hear the edit** | After you set or move **B**, the last few seconds before it (default 5 s, up to 15 s) play automatically. Skipped when the lead-in would be as long as the loop. |
| **Speed & pitch** | 0.25×–3× without changing pitch, ±12 semitones without changing speed. Settings hold a default speed/pitch for tracks you open for the first time. |
| **Repeats** | 1–999, or ∞. |
| **Your turn** | After each pass, wait as long as the loop lasts so you can repeat it aloud (shadowing), or wait a fixed time. |
| **Speed trainer** | Start at 60 %, add 5 % every 3 passes, stop at 100 %. |
| **Saved loops** | One tap restores A, B, speed, pitch, repeats and gap. Edit a loop and it shows as *changed* with **Update** / **Save as new**. |
| **Stamping** | **Marks** (verses, phrases) and nested **Minimarks** (words inside one), a **skip** flag, ±100 ms nudges, several named **stamp sets** per track (e.g. two reciters) and a **lock per tier**. Play any segment once, or loop it; skip between segments. |
| **Export for other apps** | The marker file (format v2: marks with nested minimarks, `skip`, and a SHA-256 `contentHash` computed on demand) via share sheet, *Save to file…*, or an Audacity-style label file. |
| **Routines** | A hands-free list of loops/tracks: per-step repeats (∞ allowed), pause after the step, and what happens next (continue / stop / random step / go to step N). Rounds and shuffle for the whole routine. *Play all* on a track starts one in a tap. |
| **Track queue** | ⏮ / ⏭ move to the previous/next track (natural A→Z order, so *Lesson 2* precedes *Lesson 10*). |
| **Backup & practice sheets** | One-file backup of all loops, stamp sets and routines (Settings). Per-track practice sheets to share with someone who has the same audio. Restoring matches tracks by content hash, or by name and length, and is safe to repeat. |
| **Anywhere** | Background playback, notification / lock-screen / headset controls, and *Open with / Share → Rehearse* on Android. |

## Background behaviour

Carried over from the original app, where each of these fixed a real problem:

* **Stays alive while paused.** The service remains a foreground service when
  you pause (so opening another app for a minute doesn't get the app killed),
  and lets go after **15 minutes** of no activity.
* **Swipe-away:** audio that is playing keeps playing; if nothing is playing,
  the service stops.
* **Silent waits count as playing.** "Your turn" gaps and pauses between
  routine steps hold the system wake lock, so timing stays correct with the
  screen off. Pulling out headphones or an incoming call cancels such a wait
  instead of letting audio resume from the speaker.
* **Notification:** play/pause only while practising (a stray tap can't change
  what you're editing); previous/next step appear only while a routine runs.
  Dismissing it stops playback.

## Run it

```bash
cd rehearse
flutter pub get
flutter run            # Android device or emulator
flutter test
```

Built for Flutter 3.47 / Dart 3.13 and your Gradle 9.3.1 / AGP 9.1 / Kotlin 2.4
setup.

* **Application id** is `app.rehearse`; change it in
  `android/app/build.gradle.kts` before publishing.
* **iOS / desktop** aren't set up (engine and UI are portable; background audio
  and share-sheet wiring are Android-only for now). For iOS:
  `flutter create --platforms=ios .`, then add `audio` to `UIBackgroundModes`
  in `ios/Runner/Info.plist`.
* **Material import:** Flutter 3.47 is moving Material into `material_ui`.
  Every file imports it through `lib/core/material.dart`, so adopting it later
  is a one-line change.

## How it's organised

```
lib/
  domain/    Plain Dart models and rules: Track, Loop, Marker/MarkerSet, Routine,
             Gap, SpeedTrainer, LoopRules (every limit in one place), segments.
  engine/    DrillEngine (plays one track inside A–B, counts passes, gaps, holds,
             speed ramp, play-one-range), RoutineRunner (steps, next actions),
             IdleRelease. Talks to audio only through the AudioBackend interface,
             so it is tested against a fake player on a simulated clock.
  data/      JSON document store (debounced, atomic), audio storage + importer,
             marker export v2, practice sheets, backup/restore.
  platform/  The only code touching plugins: just_audio backend, file picker /
             share, audio_service handler, Android intent bridge.
  state/     Riverpod notifiers and the two controllers the UI talks to:
             PracticeController, RoutineController.
  ui/        Screens and widgets. No business rules live here.
android/     Manifest, MainActivity (shared-audio intake), icons.
test/        154 tests: rules, engine timing, routines, idle release, storage,
             import, export, backup, and every practice-controller action on the
             real Riverpod core.
```

## Parity with the original ("Ash Player")

Everything the original did has an equivalent, except where noted.

| Original | Rehearse |
|---|---|
| Presets with lock modes, "save presets as loops" | Saved loops with *Update / Save as new*; one lock toggle for A/B |
| Sequence steps inside a preset | Routines |
| Loop-library sessions (repeat count incl. ∞, delay after, next = stop / next / shuffle / go-to) | Routines with the same per-step options (repeats incl. ∞, pause after, stop / next / random / go-to) |
| Marks + Minimarks, skip flag, marker presets, locks per tier, export v2 | Same model and export, plus a content hash the original never filled in |
| Backup of loops, presets and sessions | One-file backup & restore |
| Default speed / pitch, B-preview length | Settings |
| Previous / next track from the library | ⏮ / ⏭ |
| Foreground service while paused, 15-min release, stop on swipe-away if paused | Same (see above) |
| Open with / Share intake | Same, plus multiple files |

**Deliberately different**

* **Library is imported, not scanned.** The original listed every audio file on
  the device (MediaStore). Rehearse imports through the system picker or
  *Open with / Share*, and **copies** the audio into the app, so loops survive
  moved originals and need no storage permission. The cost is the extra disk
  space; Settings → Storage shows it.
* **Loop colours** and the "Default" protected preset aren't carried over
  (cosmetic / replaced by the loop model).

## Verification

* `dart analyze` is clean under `strict-casts`, `strict-inference` and
  `strict-raw-types` with `flutter_lints`, checked against the real sources of
  Flutter 3.47, `flutter_riverpod` 3.5, `just_audio` 0.10, `audio_service`
  0.18, `audio_session` 0.2, `file_picker` 12 and `share_plus` 13.
* All 154 tests pass.
* **Not yet run on a physical device.** Try these first: a 1–2 s loop at 0.5×
  with the screen off; pause, open another app for a few minutes, come back;
  share a voice note into the app; export timestamps and check them in the
  consuming app.
