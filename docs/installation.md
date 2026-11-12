# Installing Veylume

**English** · [Русский](ru/installation.md) · [Back to Veylume](../README.md)

## Requirements

An Apple silicon Mac (M1 or newer) running macOS 14 or later. The optional Cohere model needs macOS 15 or later. Intel Macs are not supported.

Allow about 483 MB for the default model in addition to the app. You need internet access for that first download. The app shows the real download progress and checks the files before using them.

## Install

1. [Download the DMG](https://github.com/Chernoplodich/Veylume/releases/latest/download/Veylume-arm64.dmg).
2. Drag **Veylume** into **Applications**. If you already use `~/Applications`, keep using that folder.
3. Open the installed app. Keep one installed copy. Veylume tries to eject its matching read-only installer after launch. The desktop disk icon is the mounted DMG; if it remains in use, eject it in Finder when finished.

## Opening the preview

This preview does not have Developer ID signing or Apple notarization. macOS may say it cannot verify the developer.

If you downloaded it from this repository and trust the release, try opening the installed app once. Then open **System Settings → Privacy & Security**, find the message about Veylume, and choose **Open Anyway**. Confirm the system dialog yourself. [Apple's explanation](https://support.apple.com/102445).

Do not disable Gatekeeper, remove quarantine with shell commands, install a root certificate, or import a developer's private key. If macOS reports that the app will damage your computer or has been modified, stop and report the exact warning rather than bypassing it.

## First setup

Veylume prepares Parakeet V3 automatically while you finish setup. There is no model selection quiz.

- **Microphone:** allow Veylume in the system dialog. It records only when you start a dictation.
- **Insertion and shortcuts:** open the macOS Accessibility settings from Veylume, enable the installed copy, then return to the app. Use **Check access** to see the current status. Input Monitoring is requested only if the selected shortcut path needs it.
- **Saved data, optional:** ordinary dictation and insertion need no storage password. Choose encrypted storage in General if you want vocabulary, history, or crash recovery. Enter a Keychain password only in macOS's dialog. Veylume does not have a password-entry form.
- **Shortcut:** choose your own hold shortcut. You can add a separate press-to-toggle shortcut later.

Click in a text field and try a short phrase. You can finish setup with manual copying if insertion access is unavailable.

## Update

Quit Veylume from its menu. Download the new DMG, replace the existing app in the same folder, and reopen it. Do not run another copy from the disk image. Models, settings, and local data are stored separately and are retained.

The preview has no automatic update channel. macOS may ask you to authorize a changed build again. If encrypted storage was enabled but Keychain access is lost, Veylume shows a reconnect action. Dictation and insertion remain available; history, vocabulary, and crash recovery pause until you reconnect. Your previous choices are retained. This preview cannot guarantee prompt-free access to encrypted data across personally signed updates.

## Recording indicator

Open **Settings → Appearance**. Choose **Camera cutout** to attach the indicator to the MacBook camera area. It extends sideways when there is space; if menus occupy that space, the waveform joins the cutout from below. Choose **Compact** for a separate capsule, then set **Position** to **Top** or **Bottom**. **Screen** lets you choose a display or follow the active one.

If macOS does not report a camera cutout, the settings show an explanation and Veylume uses the compact style. This also applies to external monitors. If your MacBook has a cutout but is not detected, include the display geometry from **Diagnostics** when reporting the problem. Do not send a screenshot of private messages or a transcript.

## If something does not work

Check that the model is ready and Veylume is not paused. Confirm that only one installed copy is running. Put the cursor back in the intended field and leave it there until the result arrives. Password fields can activate Secure Input; leave the protected field before starting another dictation.

If insertion is unavailable, use **Last result → Copy**. The app never sends Enter. [Report a problem](https://github.com/Chernoplodich/Veylume/issues/new/choose) with the app version, macOS version, and destination app, without sharing private text or recordings.
