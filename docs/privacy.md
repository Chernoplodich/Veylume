# Privacy

**English** · [Русский](ru/privacy.md) · [Back to Veylume](../README.md)

## Recording and recognition

Veylume records the selected microphone when you start a dictation. Stopping or cancelling ends capture; signing in, waking your Mac, or opening Settings does not start a recording. Transcription runs on your Mac with a locally installed model. There is no cloud transcription fallback.

## Network access

The first launch downloads Parakeet V3 from its model host. Optional model downloads also use their respective hosts. These services receive the ordinary network information associated with a download, such as your IP address. Veylume does not send your microphone audio or transcript to them.

The preview has no active automatic update feed. A future configured update channel will contact its release host to check for updates; it does not need dictation content. Veylume has no account, advertising system, or built-in analytics service.

## Local results

Text history is off by default. The most recent successful result stays in memory until replaced by another result or until the app exits. Enabling history stores text locally; audio is not saved as history.

New installations can dictate without persistent storage. Temporary audio is still encrypted before disk writes, using a per-recording key held in memory. Successful or cancelled recordings remove the spool; unrecoverable leftovers after a crash are cleaned on the next launch. There is no plaintext fallback.

Optional protected storage uses macOS Keychain for persistent encryption keys. It enables vocabulary, optional text history, and encrypted recovery after a failure for up to 24 hours, with a limit of ten pending results. If access needs reconnecting after an update, these features pause and dictation continues without saving new content. Previously saved settings and encrypted data are retained until deletion or their normal expiry. Encryption does not protect data from someone already able to read your unlocked session or inspect process memory.

## Insertion and the clipboard

Veylume checks the destination to avoid putting words into a different field. It does not scan documents or replace the entire field as an insertion shortcut.

Some apps require a temporary clipboard transaction for paste. Clipboard managers, Universal Clipboard, or other software with access may observe that text. A manual **Copy** also places text on the clipboard. Do not treat the clipboard as private storage.

Materialized custom formats are preserved as opaque bytes along with standard formats. File promises, unavailable providers, and snapshots over the memory limit cause automatic paste to be skipped; the original clipboard is left untouched. A later user copy always wins over restoration.

Recent macOS versions can separately restrict reading the clipboard. Veylume reports a known system denial and offers the corresponding settings action. An error retrieving clipboard items is never treated as an empty clipboard. Diagnostics include the system access policy, without reading clipboard contents.

## Permissions and diagnostics

Microphone access is for recording. Accessibility is for shortcuts and insertion. Input Monitoring is requested only when needed. Screen Recording, camera, contacts, and Full Disk Access are not required for dictation.

Technical reports contain states, durations, model identifiers, and error codes, not dictated text, audio, clipboard contents, or keystrokes. Sharing a report is your choice. Do not attach private recordings or transcripts to public issues.

## Remove data

Use **History → Erase all data** to remove Veylume's local data. Moving the app to Trash alone does not delete downloaded models and stored results. macOS permissions can be revoked in System Settings.
