# Testing AntiFish

| Suite | Command | Needs |
| --- | --- | --- |
| Unit | `make test` | nothing (model-dependent tests skip without `make models`) |
| Integration | `make test-integration` | WhatsApp Desktop linked on this Mac, Full Disk Access for the terminal, `make models` |
| CLI smoke | `make cli ARGS="status"` | same as integration |

Environment variables:
- `ANTIFISH_REAL_WA=1` — enables tests that read `~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared`.
- `ANTIFISH_MODELS_DIR` — directory holding `silero_vad.onnx` and `wespeaker_en_voxceleb_resnet34_LM.onnx` (the Makefile exports it).

Rules: tests write only under `NSTemporaryDirectory()`. Never commit audio, databases or real JIDs; `.gitignore` and the pre-commit hook enforce this.

## Verified on 2026-09-12

Unit suite: 124 tests, 0 failures, 0 skipped.
Integration suite (this Mac's real WhatsApp data): 10 tests, 0 failures, 0 skipped.

What the integration suite proves, on real voice notes rather than fixtures:

| Check | Result |
| --- | --- |
| Live `ChatStorage.sqlite` opens read-only while WhatsApp is running | yes |
| Incoming voice notes found with audio on disk | 576 |
| Every recent Ogg-Opus note decodes through AVFoundation | yes |
| Same-speaker vs different-speaker separation, raw cosine | 0.18 |
| Same-speaker vs different-speaker separation, centred | 0.70 |
| Contacts enrolled from real audio | 28 |
| Calibration: genuine median vs impostor median | 0.60 vs -0.05 |
| Notes from a saved, enrolled contact that verify | 18 of 20 |
| False impersonation alarms on those notes | 0 |
