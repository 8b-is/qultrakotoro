# Privacy — qUltraKotoro

Speech recognition in this revision requires an available Apple on-device model.
Requests fail when local recognition is unsupported; there is no cloud fallback.
Microphone capture requires permission. File transcription requires speech
recognition permission but does not request microphone access.

The app does not implement telemetry, analytics, accounts, or transcript sync.
Live audio is held in memory; settings are stored locally in UserDefaults.
Opening setup, source, or other external links sends ordinary browser requests
to those websites. The optional model-download script contacts Hugging Face;
its downloaded models are not yet connected to a transcription engine.

`scripts/check-offline.sh` is a source lint check for common networking APIs.
It is not a sandbox, network monitor, or proof of framework behavior. Validate
recognition offline on each supported device and language before release.
Earlier revisions did not enforce the on-device requirement when unsupported.

## Contact

Open a discussion or a [security advisory](SECURITY.md).
