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
