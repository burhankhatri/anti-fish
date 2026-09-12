# AntiFish, explained in plain words

What every piece is, what it does, and why we chose it. Written so you can read a line
out loud and have a non-technical judge understand it.

---

## 1. The shape of the whole thing

| Piece | What it is | Why |
| --- | --- | --- |
| Swift 6 + SwiftUI, macOS 15 | The app itself | Native means fast, and it can reach the local files the whole idea depends on |
| `AntiFishCore` (a Swift package) | All the thinking | The screen only draws. Every decision lives in code we can test, and 267 tests do |
| System SQLite | Our own memory | Already on every Mac, no dependency to install, survives a restart |
| No account, no server | — | Nothing to breach, nothing to subpoena, works on a plane |

**The line to say out loud:** the app never uploads your conversations. It reads what is
already on your Mac and answers on your Mac.

---

## 2. Where the data comes from

WhatsApp Desktop keeps everything in a SQLite database inside its own container. We open
that file **read-only** and never copy it.

- `ChatStorage.sqlite` — messages, including which ones are voice notes
- `ContactsV2.sqlite` — names and profile pictures
- A voice note is a message whose type is `3`. Images are `1`, video `2`, documents `8`

**Why read-only matters:** WhatsApp is writing to that file while we read it. SQLite's
write-ahead log makes reading safe, and we can never corrupt their data because we never
hold a write lock.

---

## 3. Voice: turning a person into numbers

This is the heart of the project. Four steps.

**Step 1 — find the speech.** A voice note contains breath, silence and room noise.
**Silero VAD** (voice activity detection) marks which parts are actually speech, and we throw
the rest away. Compressed audio is decoded to 16 kHz mono first.
*Why:* silence has no voice in it, and averaging it in blurs the person.

**Step 2 — make the fingerprint.** The speech goes through **WeSpeaker ResNet34-LM**, a
speaker-recognition model, running offline as an **ONNX** model through **sherpa-onnx**. Out
comes **256 numbers**.
*Why this model:* it is trained to answer "is this the same person", not "what did they say".
It never transcribes anything.
*The layman line:* it measures the shape of the voice, the way a throat and mouth colour a
sound, not the words.

**Step 3 — centre the numbers.** We subtract the average of all enrolled voices from every
fingerprint before comparing.
*Why this is the single most important trick:* raw, two different people scored 0.18 apart,
which is almost nothing. Centred, the same two sit **0.70** apart. Everything that comes from
one microphone and one room looks alike; subtracting the average removes what everyone shares
and leaves what makes a person different.

**Step 4 — compare.** Similarity is **cosine similarity**: 1.0 is identical, 0 is unrelated.
A new note is scored as **half against the middle of the person's cluster, half against the
average of their three closest notes**.
*Why both:* the middle is stable but blurry, the nearest notes are sharp but noisy. Using both
cut our error from 12.7% to 10.4%.

---

## 4. The graphs on the slides, and what they mean

**The fingerprint grid (256 squares).** Each square is one of the 256 numbers, brightness is
its value. It is a picture of what a voice looks like to the app. Nothing readable, nothing
reversible back into audio.

**The clusters.** Every dot is one voice note that person actually sent you. The dark dot in
the middle is their baseline. The picture makes the whole idea obvious: **a person is a
cluster, an impostor lands outside it.** Momina's cluster is drawn smaller because she has
five notes; the app treats a thin baseline as thin.

**The two hills.** After enrolment the app scores your contacts against themselves and against
each other, producing two distributions:

| | Where it sits on this Mac |
| --- | --- |
| Same person | about **0.60** |
| Different person | about **&minus;0.05** |
| The line | **0.36** |

The line is placed where the two hills overlap equally, the **equal error rate**. That is the
point where a miss and a false alarm are equally likely, about **one call in nine** either way.
*Why we say the error rate out loud:* a tool that hides its error rate is asking to be trusted
blindly, which is the exact habit that gets people scammed.

**Why one line and not two.** An earlier version had a middle band that said "inconclusive".
We measured it: **54%** of genuine notes fell in that band. A verdict that lands on "don't
know" half the time is not a verdict, so we removed it.

---

## 5. The claim dropdown

An unknown number is not a name. So you tell the app the name the sender is claiming, and the
app answers **about that person**.

**The bug worth telling:** an early build answered about whoever scored highest. Asked "is this
Momina?", it replied "this really is Shifa". Now naming someone decides the answer, and a
closer match is only mentioned after your question has been answered.

---

## 6. Pictures

Two different checks, because there are two different lies.

**The lie in the pixels** — a generated image. Checked with **SightEngine's `genai` and
`deepfake` models**, the same service the deepfake-check project uses.

**The lie in the text** — a real screenshot with edited numbers, which no pixel model catches,
because the pixels are a genuine screenshot. We read the text inside the picture with
**Apple's Vision framework** (`VNRecognizeTextRequest`), on device, no quota, and judge what it
says: a transfer amount, an account number, an urgent instruction.

*The honest caveat:* the pixel check is the one part that leaves the Mac, and only when you
press the button. When it cannot run, the result is **amber, never a green tick** — a check
that did not happen is not a pass.

---

## 7. Video

A video is checked by checking frames inside it, through the same image check.

**Where the frames come from matters more than how many.** Measured on five labelled clips:

| Method | Result |
| --- | --- |
| Three frames from the opening | Called a real selfie AI-generated at 0.99 |
| Five frames spread across the clip | Five out of five correct |

*Why:* an opening frame is often dark, blurred or half-rendered, which looks synthetic to any
model. Frames come out with **AVAssetImageGenerator**, and the thumbnail shown in the chat is
taken a second in for the same reason.

---

## 8. Email

Every message already on the Mac, read in place from **Mail.app's `.emlx` files**. Twenty-five
checks in five layers.

| Layer | What it asks | Examples |
| --- | --- | --- |
| **L0 Protocol** | What the mail servers can prove | SPF, DKIM alignment, DMARC, Reply-To divergence, Received chain |
| **L1 Identity** | Is this who it says | Display-name mismatch, lookalike domain, homoglyphs, freemail persona, first contact |
| **L2 Fingerprint** | Is it really them | Mail client, Message-ID shape, header order, an **80-number writing-style vector** compared against that sender's own history |
| **L3 Payload** | What it wants you to open | Link text vs real destination, redirect chains, attachment types, hidden text, credential forms |
| **L4 Intent** | What it is actually asking | Payment redirection, credential request, manufactured urgency, secrecy, injected instructions |

**How the layers combine.** Findings are pooled with weights, so no single signal is ever proof
on its own.

**The one rule that made it work: reassurance is scoped to its own layer.** A passing signature
can never excuse an identity mismatch, because **an attacker sending from their own domain
authenticates perfectly**. Getting this wrong is why most filters cry wolf.

**Measured on a real 2,298-message mailbox: false alarms fell from 64.8% to 3.2%.**

*A failure we fixed on the way:* the first version ranked newsletters as more dangerous than
real phishing, because link-shape rules fired on legitimate marketing mail. One rule appeared
on five legitimate senders and zero phishing ones. Now a message whose only marks are
link-shape, with no hard evidence anywhere else, is downgraded.

---

## 9. What we are honest about

- **Voice scoring is about 11% wrong either way**, and a thin baseline is worse. The app says
  when a baseline is thin instead of guessing.
- **A modern voice clone can pass.** The structural defence is that a number you have never
  saved never gets a green verdict, no matter how good the imitation sounds.
- **The pixel check can be out of quota or offline.** Those render amber, never green.
- **Screenshots with edited text** are caught by reading the text, not the pixels, which is why
  both checks exist.

---

## 10. One-sentence answers for the Q&A

**"What if the AI is trained on my own voice?"**
Then it may pass the voice check, which is why the verdict also depends on *where the message
came from*. An unsaved number never goes green.

**"Why not just use a cloud API for all of it?"**
Because the data is the user's whole private life, and the people most likely to be scammed are
the least able to consent to that. Voice, mail and text never leave the Mac.

**"How do you know your thresholds are right?"**
We do not set them. The app measures your own contacts after enrolment and puts the line where
the two distributions cross.

**"What happens when a check fails?"**
It shows amber and says why. A check that did not run never looks like a pass.
