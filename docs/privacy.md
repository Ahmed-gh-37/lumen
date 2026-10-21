# Data and privacy

## What stays on this Mac

Lumen creates its runtime data outside the source repository:

```text
~/Library/Application Support/Lumen/
  workspace.json   Notes, chat text, scripts, and preferences
  ChatGPT/         The separate app-server sign-in profile
  Assistant/       The app-server working directory
```

The workspace is written atomically, with restricted file permissions. A damaged or unsupported workspace produces an error and is preserved rather than silently replaced.

Gemini and Claude keys are kept in macOS Keychain, not in the workspace or repository. ChatGPT authentication belongs to its separate app-server profile. Treat that profile as sensitive; do not share it.

Screenshots and raw audio are not written to the workspace. A screenshot remains in memory until sent, removed, or released. Listen transcripts are saved as notes when you end a session. Teleprompter voice follow does not save its recognition transcript.

## What leaves this Mac

When you use an AI feature, Lumen transmits the request's text, selected context, and any attached screenshot to your chosen provider. Automatic screen explanations do this for each successful capture while the session is running. Provider handling and retention are governed by your account and the provider's policies.

Apple's on-device speech recognition handles Listen and script following. If local recognition is unavailable, Lumen reports an error; it does not silently switch to cloud speech recognition.

**Pause AI** cancels the active request and stops new AI requests. Notes and local transcription remain usable. Pausing cannot retract content already transmitted.

## Sharing your screen

Lumen can request exclusion through AppKit's public sharing flag. This is not a guarantee of exclusion from ScreenCaptureKit, conferencing software, recordings, or screenshots. Check using the capture app you actually use. See [Apple's sharing-type documentation](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum).

Lumen is a normal macOS application. Its process remains visible to Activity Monitor and other system tools.

## Exporting and removing data

Export a note through its menu as Markdown or PDF. Delete individual notes through the note editor. Remove optional API keys with the delete control in provider Settings, and disconnect ChatGPT through its own control.

To erase all local workspace content, quit Lumen and remove its Application Support folder. This includes saved notes, conversations, scripts, preferences, and its local sign-in profile. Export anything you want to keep first. Removing local files does not delete copies already sent to a provider.

Source builds exclude runtime files, credentials, signing certificates, and build output through `.gitignore`. Never add your Application Support folder or authentication profile to a bug report.
