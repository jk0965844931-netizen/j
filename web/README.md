# Babelfish Live Web

A working browser version of the Babelfish Live room-microphone flow shown in the reference image.

## Run locally

```bash
node web/server.js
```

Open <http://localhost:4173>. The app serves a static mobile-first UI plus a small Server-Sent Events room hub so another browser/device can open the copied room link and receive the same live transcript/translation.

## What works

- Browser microphone capture through the Web Speech Recognition API.
- Live room sharing over the built-in Node.js SSE server.
- Speech playback through `speechSynthesis`.
- Room input meter through the Web Audio API.
- Translation via a user-provided LibreTranslate-compatible endpoint, the browser Translator API when available, and a small phrasebook fallback for common demo phrases.

> Microphone and speech-recognition support depends on the browser. Chrome and Safari currently provide the best support.

## PC game hook overlay prototype

The web app can also act as a desktop companion for a game-text hook or OCR bridge. It follows the same high-level flow used by tools such as LunaTranslator: capture text from the running game, translate it, then either display the translated result in a separate overlay or preview an embedded-style replacement over the game's text box.

1. Start the local server:

   ```bash
   node web/server.js
   ```

2. Open <http://localhost:4173>, choose the source/target languages, then set **Translated text output** to:
   - **Overlay after translation** for a floating browser window that can be kept above a PC game.
   - **Embedded-style replacement preview** to hide the app overlay and show the translation as if it replaced the game's text box.
   - **Overlay + embedded preview** to show both.

3. Click **Open overlay window** and keep that small window over the game. The overlay URL is the same room with `?overlay=1`.

4. Send hook/OCR output to the room bridge endpoint. For example:

   ```bash
   curl -X POST http://localhost:4173/api/rooms/ROOM_ID/hook \
     -H "content-type: application/json" \
     -d '{"text":"Welcome to the old shrine. Are you ready?","sourceLanguage":"en","targetLanguage":"th","displayMode":"overlay","processName":"game.exe"}'
   ```

5. The controller page translates the hook text using the configured LibreTranslate-compatible endpoint, the browser Translator API when available, or the demo phrasebook fallback, then publishes the translated message to the overlay window.

This repository does **not** inject code into games itself. A native Windows hook/OCR bridge can post captured text to `/api/rooms/:roomId/hook`, which keeps the UI layer separate from game-specific injection, font, encoding, and crash-safety concerns.
