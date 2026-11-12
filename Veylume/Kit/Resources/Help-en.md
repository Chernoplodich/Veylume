Veylume runs transcription on your Mac. Parakeet TDT V3 downloads automatically once; use Models for optional alternatives. Speech text and audio are not sent to a transcription server. Model downloads and optional signed update checks use the network.

Choose a shortcut during setup. Hold records only while held; Toggle starts on one tap and stops on the next. Escape cancels capture and invalidates a late result. The system microphone indicator is authoritative. Menu recording always has an explicit Stop control.

Grant Microphone for capture. Accessibility is used for destination checks and insertion. Input Monitoring is requested only for an assigned global shortcut. Posting Paste is checked separately. Grant permissions yourself in System Settings → Privacy & Security. Secure Input is respected. No Screen Recording or Speech Recognition access is needed.

Place the caret before recording. Moving the pointer alone does not change the destination. Changing the field, window, application, or observable selection skips automatic insertion. Copy remains explicit. Paste is never retried automatically and never sends Enter. Terminal/console payloads are flattened to one line and stripped of control sequences. Clipboard managers may see transient paste data. If consumption cannot be verified, the paste payload remains on the clipboard to avoid a premature restore.

The last completed result remains in RAM until the next success or exit. Errors and cancelled sessions do not replace it. Persistent storage is optional and off for new installations. Enable encrypted storage in General to use vocabulary, optional text history, and crash recovery. Statistics remain independent, content-free session counters.

Temporary audio is encrypted before disk writes with a per-recording key kept in memory. Without connected storage, success or cancellation removes the spool; a crash leaves no recoverable key, and leftovers are cleaned on next launch. Connected recovery wraps that key with Keychain protection and keeps at most ten results for up to 24 hours. Existing protected data is retained until deletion or expiry. APFS snapshots/backups are not secure erase. Retry never automatically pastes into an old destination.

Cohere requires an explicit supported language and does not support Russian. Its decoder token limit is checked. No result marked incomplete is automatically pasted. Other models retain their own language capabilities. Vocabulary hints are currently unavailable in these bundles; literal replacements are supported.

Local builds use a development identity and have not been notarized. A production release needs the owner’s Developer ID, stable Bundle/Team identity, HTTPS hosting and EdDSA update key. Automatic checks are enabled as a preference, but no request is made until a real signed feed is configured. Installation and restart require your action and wait for safe idle.

To uninstall, first disable Launch at login. Use History → Erase all data if you want to remove models, dictionary, history, recovery, statistics and preferences. Moving Veylume.app to Trash removes only the application; its local data and macOS permissions may remain. Veylume does not reset TCC or remove quarantine.

Dependencies: FluidAudio (Apache-2.0), Argmax OSS/WhisperKit (MIT), Sparkle (MIT), Swift Argument Parser (Apache-2.0). Parakeet conversion: FluidInference, CC-BY-4.0; NVIDIA model authors credited in its bundled model card. Cohere conversion: FluidInference/Cohere, Apache-2.0. Whisper conversions: Argmax/OpenAI, MIT; local tokenizer model cards accompany the verified catalogue. Original provider monograms are identification labels, not official logos. See Acknowledgements for source URLs and notices.

Setup checks microphone and insertion access. Saving is optional. If an update needs renewed Keychain access, Veylume shows that saving was enabled and offers to reconnect it. Dictation and automatic insertion continue; history, vocabulary, and recovery pause until access returns. Your previous choices stay in place. Connect secure storage opens the genuine macOS prompt if needed; enter your password only there. The originating window returns after your confirmation, unless you closed it.

Interface language: choose English, Russian, Spanish, French, or System in General. This does not change the model’s supported speech languages.

In Appearance, choose Camera cutout to join the indicator to a MacBook’s camera area. It extends to the sides when there is room, or below the cutout when menus occupy that space. Choose Compact for a separate capsule at the top or bottom of your selected screen. If macOS does not report a cutout, Veylume uses the compact style and explains this in Settings. Click the indicator for stop and cancel controls.

Opening a new DMG does not update the installed copy by itself. Quit Veylume, replace it in the same Applications folder, then open that copy. Models and settings remain. A new personally signed build can still ask for Keychain access again; the same build’s ordinary relaunch should not require a password. Never enter passwords into Veylume itself.

The recording bars react together to the current microphone level, without scrolling history. After launch from Applications, Veylume tries to eject its exact matching read-only installer disk. The downloaded DMG is not deleted; if it remains in use, eject it in Finder.
