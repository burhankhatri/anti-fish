# Demo assets

Every file here was run through the app's own checks and the result recorded. Nothing is included
on the assumption that it works.

| File | What it demonstrates | Verified result |
| --- | --- | --- |
| `fake-payment-easypaisa.png` | The scam no pixel model sees: a payment receipt is a real screenshot with edited numbers | **Flagged** — "It claims money has been sent. It pushes you to act immediately." Local, no quota |
| `fake-payment-bank.png` | Same, larger amount | **Flagged**, same two signals |
| `ai-generated-image.jpg` | A generated image | **AI-GENERATED**, 0.99 |
| `ai-generated-video.mp4` | A generated clip | **AI-GENERATED**, 5 of 5 frames |
| `face-swapped-video.mp4` | A face swap from the DFDC set | **FACE-SWAPPED**, 1 of 5 frames |
| `real-video.mp4` | A real phone selfie, to show it clears things too | **Authentic**, 0 of 5 frames |
| `synthetic-voice.opus` | Machine-made speech | **Sounds machine-made: yes** |
| `synthetic-voice-that-slips-through.opus` | The same sentence in another synthetic voice | **Missed.** Kept deliberately, so the limit is demonstrable rather than hidden |

The last row matters. The synthesis check catches 7 of 10 synthesised clips and wrongly flags 1 of
40 real ones. It is not a voice-clone detector: a modern clone models breath and prosody and will
pass it. The defence against that is structural — a number the user has not saved never receives a
green verdict, however convincing it sounds.

Payment-proof detection is the one that works with no service, no key and no quota, because it
reads the words rather than the pixels.
