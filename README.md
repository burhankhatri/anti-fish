# AntiFish

Flags WhatsApp voice notes whose voice does not match the apparent sender.

A stranger can put someone's name and photo on a new number and send you a voice note. AntiFish
builds a voice fingerprint for the people who actually send you voice notes, then scores every
incoming note against them. Two sides: WhatsApp voice notes, and the email already in Mail.app. Almost all of it runs on this
Mac. The one exception is the image check, which sends the picture to SightEngine and stays off
until keys are configured; the interface says so wherever it appears.

## What it checks

| Where | What | How |
| --- | --- | --- |
| WhatsApp | Voice notes | Speaker fingerprints built from the people who actually send you voice notes |
| WhatsApp | "They say they're Abdul" | You name who the caller claims to be; the app tests that claim |
| Email | Every message Mail.app has | [PhishGuard](https://github.com/shahmeer-irfan/phishguard), run unmodified over the local store |
| Both | Shared images | [deepfake-check](https://github.com/abdulrehmann231/deep_fake) via SightEngine, off by default |
| Both | Shared video | Frames pulled with ffmpeg and checked as images; five spread across the clip got all five labelled clips right |
| Both | What a message *says* | Scam patterns in English and Roman Urdu, on this Mac, no service and no quota |
| Both | Words inside a picture | Apple's recogniser reads the screenshot, then the same scam patterns judge it |

A doctored payment screenshot is the case pixel analysis cannot see: nothing about it is
generated, so a deepfake model calls it real. What gives it away is that it says money was sent.
Reading the words catches it, and costs nothing.

## What it catches

- An unsaved number whose profile name claims to be someone you know, but whose voice is not theirs.
- A saved contact's own number sending a voice that is not theirs, which is what an account takeover
  sounds like.
- An unsaved number whose voice *does* match someone you know, so you can confirm on their real
  number before acting.

AI voice clones are out of scope for now: a convincing clone of a real contact will verify.

## How it decides

Voice notes are decoded to 16 kHz mono, trimmed to just the speech, and turned into a 256-dimension
fingerprint by an offline speaker model. Comparisons happen in a centred space, because raw
embeddings score every pair of voices at 0.65-0.90 and separate almost nothing. Centring is what
makes the numbers mean something: measured on ten real speakers, the gap between same-speaker and
different-speaker scores widens from 0.18 to 0.70.

Thresholds are not hardcoded guesses. After enrolment, AntiFish measures how this user's own
contacts score against themselves and against each other, and puts the lines where those two
distributions actually sit.

## Try it

```
make models          # fetch the two ONNX models (~27 MB, checksummed)
make cli ARGS="status"
make cli ARGS="enroll"
make cli ARGS="verify --newest 5"
make cli ARGS="feed 10"
```

`enroll` needs Full Disk Access for your terminal, because macOS keeps WhatsApp's files private to
WhatsApp.

## Layout

- `AntiFishCore/` — all the logic, as a Swift package. No UI.
- `docs/specs/` — the design, including the facts it rests on.
- `docs/plans/` — implementation plans.
- `testing.md` — how to run each suite.

Only third-party dependency: [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) for the speaker
and voice-activity models. Storage is the system SQLite.
