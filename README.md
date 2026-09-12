# AntiFish

Flags WhatsApp voice notes whose voice does not match the apparent sender.

A stranger can put someone's name and photo on a new number and send you a voice note. AntiFish
builds a voice fingerprint for the people who actually send you voice notes, then scores every
incoming note against them. Everything runs on this Mac: it reads WhatsApp Desktop's local
database and audio files, and never uses the network.

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
