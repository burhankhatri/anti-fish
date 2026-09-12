# AntiFish

macOS app that flags WhatsApp voice notes whose voice does not match the apparent sender. Spec: `docs/specs/2026-09-12-voice-note-impersonation-design.md`. Plans: `docs/plans/`.

- Core logic lives in the Swift package `AntiFishCore/`; the app renders only.
- `make test` (unit), `make test-integration` (real WhatsApp data, local only), `make models` (fetch ONNX models).
- Never commit anything from the WhatsApp container. Fixture JIDs are short fakes like `111@lid`.
- WhatsApp facts: voice notes are `ZMESSAGETYPE = 3`; media paths are container-relative; the live `ChatStorage.sqlite` is opened read-only, never copied.
- Do not add co-author trailers to commits.
- Follow the global CLAUDE.md workflow: failing test first, root cause before fixes, fresh verification before claiming done.
