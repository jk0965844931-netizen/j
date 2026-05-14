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
