# Contributing

Bug reports in English or Russian are welcome. Include the Veylume version, macOS version, destination app, and short reproduction steps. Do not attach private dictations, recordings, clipboard data, passwords, or signing material.

For code changes, keep the scope focused and explain the resulting behavior and how you checked it. [Build instructions](docs/building.md) · [Инструкция по сборке](docs/ru/building.md).

## Recording and insertion

- Hold and toggle are distinct gestures. Releasing a hold shortcut must stop capture, including during preparation.
- Escape cancels the active session. A late recognition callback must not paste after cancellation.
- Keep one active session and at most one automatic insertion attempt.
- Preserve the destination. If the app, field, or detectable selection changes, keep the result for manual copying.
- Never send Enter, submit a form, execute a command, or replace an entire field to insert text.
- Restore clipboard data only while the app still owns the transaction. Never overwrite a newer user copy.
- Do not log speech, transcripts, clipboard contents, keystrokes, or personal paths.
- Use public macOS APIs and preserve system permission and Secure Input boundaries.

Use native SwiftUI/AppKit for product UI. Keep heavy work off the main actor and avoid idle polling. Check affected behavior and run `bash scripts/test.sh` before submitting a change. UI fixtures do not replace microphone, insertion, or physical-display testing.

Contributions are made under the repository's MIT license. Keep upstream copyright and license notices intact.
