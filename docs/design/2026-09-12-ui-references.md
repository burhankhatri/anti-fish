# AntiFish UI — design references

Sourced from Mobbin on 2026-09-12. Each rule below is taken from a shipped app, named.

**Governing principle.** Calm apps put state in the icon slot or a trailing low-saturation capsule
and reserve colored backgrounds for the one row that is actually bad. Alarming apps color the text.
We do the former.

## Feed rows

- **Upside, Activity** — trailing capsule with a tinted fill and near-black text, not colored text.
  A screen of twenty rows stays still. This is the verdict pill.
- **Glow, Activity** — the failed row swaps only its leading glyph and changes nothing else. This is
  the treatment for "unknown voice".
- **Truecaller, scammer profile** — a shield glyph plus label, subtitle rank rather than title rank.
  Take the pill; leave the giant red circle, which over-claims.
- **Shopee, Check Account Activity** — a full-width pale wash on the flagged row. Reserved for a
  suspected impostor, which should be rare.

Rules: omit the pill entirely for ordinary rows, so most rows carry none. Never use red in the list;
orange is the strongest colour there. Red belongs only to the report action in the detail sheet.
No unread dots, no counts.

## Detail sheet

- **Revolut Business, Confirm Login** — identity card, then a card of caveat rows, then two actions
  where neither is red or filled. States facts, hands judgment to the reader.
- **Cash App, "Did you make this payment?"** — actions phrased as full sentences in the user's
  voice. Ours become "Yes, this is really Ana" and "Report impostor", not "Confirm" and "Reject".
- **Chase UK, Before you add this payee** — the dangerous action is red text, never a red filled
  button.
- **Zing, Friends & Family** — evidence listed as criteria the reader evaluates, not as conclusions.

Language: soft verb, hard number. "This voice doesn't match Ana", with the sample count and score
stated underneath. Never "Fraud detected".

## Score meter

- **Superpower, Vitamin D** — a shaded band with dashed threshold lines at both edges, the value a
  small marker on it, and the thresholds spelled out beneath. Our two learned thresholds map onto
  its two lines.
- **Noom, Body fat percentage** — only the active segment is coloured; the rest stay grey. That grey
  rule is what keeps a meter from looking alarming.
- Avoid **Garmin's HRV arc**: a speedometer implies more precision than a cosine similarity has.

## Audio rows

- **Pillow, Recordings** — play button leading, no waveform in the list, machine label in a trailing
  pill. Our verdict pill sits where its category tag sits.
- **TextNow** — in the detail sheet, the waveform is the scrubber: played bars solid, unplayed faint.
- No dancing equaliser during playback; it undercuts the tone.

## Contacts

- **monday.com, Users** — tier as plain grey text, no capsules. Capsules are for the feed; a roster
  gets restraint.
- **Discord, Thread members** — section headers carry counts.
- **Mozi, My People** — per-row actions revealed rather than hidden behind a swipe. On macOS that
  means hover-revealed pin and remove, plus a context menu. No swipe actions.

## Full Disk Access onboarding

Mobbin has no macOS coverage; these come from shipped Mac apps.

- **CleanShot X, Raycast, Rectangle** — a persistent checklist that updates itself. A row per
  permission, a button that deep-links to the exact pane, and a row that flips on its own within a
  second. Never a modal that blocks, never an "I've done it" button.
- **Bartender 5** — shows a picture of the System Settings pane, because the toggle is in a long
  list and that is where people get lost.
- **Mercury, Application in review** — finished steps move to a completed section, greyed with a
  check. Gives the auto-detection something satisfying to do.

Two details real apps get right: macOS may need a relaunch after the grant, so offer a relaunch
button rather than spinning forever; and offer a way to skip, because onboarding you cannot dismiss
reads as malware.

## Deliberately avoided

Red as a list colour and threat iconography. Any aggregate "security score", which invents a number
nothing measures. Mascots, unread badges, animated equalisers.
