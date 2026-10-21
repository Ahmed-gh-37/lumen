# Using Lumen

## Connections

### ChatGPT

Install the Codex desktop app, a compatible ChatGPT desktop app, or Codex CLI. In Lumen, open **Settings → ChatGPT → Continue with ChatGPT**, complete the browser sign-in, and return to the panel. Lumen checks automatically; **Check connection** refreshes it manually.

Lumen talks to the installed Codex app-server using its public protocol and a separate authentication profile. It does not read your existing Codex credentials or configuration. Plan eligibility, usage limits, and available models come from the connected account. Disconnect through Lumen Settings.

The connection uses [OpenAI's sign-in integration](https://developers.openai.com/cookbook/articles/sign-in-with-chatgpt) and the [Codex app-server protocol](https://developers.openai.com/codex/app-server/). Changes to the installed helper can affect compatibility.

### Gemini and Claude

Choose the provider in Settings, enter your key, and select **Save**. Keys are stored in macOS Keychain. Use the remove button to delete a saved key. The editable model field accepts the model ID available to your account; consult [Gemini's model catalog](https://ai.google.dev/gemini-api/docs/models) or [Claude's model catalog](https://platform.claude.com/docs/en/models/overview).

API usage is billed separately by the provider. A provider change cancels the current answer and stops automatic screen explanations.

## Permissions

| Permission | Used for | When it starts |
| :--- | :--- | :--- |
| Screen Recording | Screen attachments, screen explanations, and system-audio capture | After you request a capture or start the corresponding session. |
| Microphone | Microphone Listen and teleprompter voice follow | After you start listening or following. |
| Speech Recognition | Apple's on-device transcription and script matching | Alongside the corresponding audio session. |

In Settings, **Check access** asks ScreenCaptureKit whether access is available. It does not capture or send a screenshot. **Screen Recording settings** opens macOS permissions; **Show this app** reveals the build that needs access.

If macOS still denies screen access after a rebuild, check that its permission entry points to the current app. Changing signing identities can require granting access again. Lumen does not alter macOS's privacy database or security settings.

On-device speech recognition must be available for the chosen language. Lumen reports unavailable recognition instead of falling back to cloud transcription.

## Screen context

**Capture screen** prepares a screenshot attachment. **Explain my screen** captures and sends it immediately. Choose a display when multiple screens are connected. Lumen excludes its own windows from its own captures.

**Automatic screen explanations** start with an immediate send, then attempt one every 60 seconds. Busy minutes are skipped without a queue or overlapping requests. The cap is 60 successful sends, so a busy session can last more than an hour. Use its shortcut again, the session banner, Settings, or the menu to stop.

An error, Pause AI, a provider change or disconnect, or quitting ends the session. Starting again resets the counter. No session resumes on launch. Each request contains the current screenshot and recent text context, and uses the connected plan or API allowance.

## Listen

Choose Microphone or System audio, select the speech language in Settings, and start a session. **Pause answers** keeps transcription running while stopping generated suggestions. Ending a session saves the transcript as a local note.

Automatic draft answers are optional. **Listen context** controls whether the current transcript accompanies an Ask request. **Pause AI** cancels generation and prevents new AI requests while leaving local notes and transcription available.

## Teleprompter

Open Prompter and paste your script, or import a completed answer. Script, text size, scroll speed, and voice-follow preference are saved locally.

With **Follow my voice**, nearby recognized script phrases move the reader forward. Silence and unrelated speech leave the reading position in place. There is no speech output or AI request in this mode, and its transcript is not saved. Use a close microphone: it cannot identify the speaker, and another voice saying matching words can advance the script.

Turn voice follow off for timed scrolling. Pause keeps your place; **Restart** returns to the beginning. Editing, leaving Prompter, hiding the window, or quitting pauses playback and releases the microphone. Listen and voice follow cannot use audio simultaneously. Playback does not start on launch.

## Notch and click-through

The notch button beside Settings moves the whole app to the top-center of the display. Hover to expand; moving away collapses it after a short delay when Lumen is not focused. Editing, shortcut recording, size controls, and active teleprompter playback keep it open.

Set the width and 2–8 reading lines in Settings or the compact reader's size control. **Full controls** pauses playback and opens the script editor. **Return to floating window** restores the previous floating position. Displays without a camera notch use a top-center tab. The opacity slider applies to both layouts.

Mouse click-through leaves Lumen visible while clicks reach the windows underneath. Use the same shortcut again, or **Lumen → Mouse click-through**, to restore interaction. Reopening Lumen from its menu restores interaction too. Click-through starts off on each launch.

Capture exclusion uses the public AppKit sharing flag. Modern capture and conferencing apps may still include the window. Test with your actual meeting app before relying on it. Hiding the panel or enabling click-through does not hide the process from Activity Monitor.

## Building and signing

Run `bash scripts/package-app.sh` from the repository root. The result is `build/Lumen.app`, built for the host Mac's architecture with a minimum macOS version of 14.

The script prefers Developer ID Application, then Apple Development, and finally ad-hoc signing. To select a certificate explicitly:

```sh
LUMEN_SIGNING_IDENTITY="YOUR_SIGNING_IDENTITY" bash scripts/package-app.sh
```

Stable signing helps preserve permission grants across updates. Ad-hoc builds can require renewed access after changes. The script verifies the signature but does not notarize the app or prepare an App Store submission. A development-signed local build is not a notarized public installer.
