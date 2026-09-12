# Vendored

Third-party code, unmodified, kept here so AntiFish runs the original logic rather than a
re-implementation of it.

| Path | Source | Used for |
| --- | --- | --- |
| `phishguard/` | [shahmeer-irfan/phishguard](https://github.com/shahmeer-irfan/phishguard) | Email phishing detection, layers 0-3 |
| `deepfake/detect.py` | [abdulrehmann231/deep_fake](https://github.com/abdulrehmann231/deep_fake) | Image AI-generation and face-swap checks |

PhishGuard ingests from Gmail over OAuth. AntiFish does not need that: Mail.app has already
downloaded the messages, so `Tools/phishbridge.py` reads those `.emlx` files and feeds the raw
RFC822 bytes into PhishGuard's own store and detection layers. Only the ingest is different; every
verdict comes from PhishGuard.

The deepfake check calls SightEngine, which means the image leaves this Mac. That is the one part
of AntiFish that uses the network, it is off unless configured, and the interface says so.
