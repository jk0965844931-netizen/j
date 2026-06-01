const $ = (id) => document.getElementById(id);

const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
const synth = window.speechSynthesis;
const params = new URLSearchParams(window.location.search);
const generatedRoom = crypto.randomUUID ? crypto.randomUUID().slice(0, 8) : Math.random().toString(16).slice(2, 10);
const roomId = (params.get('room') || generatedRoom).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 48);
const overlayOnly = params.get('overlay') === '1';

const languageNames = new Intl.DisplayNames([navigator.language || 'en'], { type: 'language' });
const state = {
  roomId,
  recognition: null,
  listening: false,
  speaking: false,
  eventSource: null,
  audioContext: null,
  analyser: null,
  meterFrame: null,
  mediaStream: null,
  history: JSON.parse(localStorage.getItem(`babelfish:${roomId}:history`) || '[]'),
  hookQueue: Promise.resolve(),
  overlayWindow: null
};

const phrasebook = new Map([
  ['en|th|hello, how are you?', 'สวัสดี คุณสบายดีไหม?'],
  ['en|th|hello', 'สวัสดี'],
  ['en|th|thank you', 'ขอบคุณ'],
  ['en|th|good morning', 'อรุณสวัสดิ์'],
  ['en|th|where is the bathroom?', 'ห้องน้ำอยู่ที่ไหน?'],
  ['th|en|สวัสดี', 'Hello'],
  ['th|en|ขอบคุณ', 'Thank you'],
  ['th|en|คุณสบายดีไหม', 'How are you?'],
  ['th|en|ห้องน้ำอยู่ที่ไหน', 'Where is the bathroom?'],
  ['en|ja|hello', 'こんにちは'],
  ['en|ko|hello', '안녕하세요'],
  ['en|zh|hello', '你好'],
  ['en|es|hello', 'Hola'],
  ['en|fr|hello', 'Bonjour'],
  ['en|de|hello', 'Hallo']
]);

function init() {
  $('roomId').textContent = roomId;
  $('deviceHint').textContent = `${detectDevice()} detected: guided room-mic flow enabled`;
  updateLanguageLabels();
  renderHistory();
  connectRoom();
  bindEvents();
  configureOverlayMode();

  if (!SpeechRecognition) {
    toast('Speech Recognition is not supported in this browser. Try Chrome or Safari.');
    $('startButton').disabled = true;
    $('captureButton').disabled = true;
  }
}

function detectDevice() {
  const ua = navigator.userAgent;
  if (/iPhone/i.test(ua)) return 'iPhone';
  if (/iPad/i.test(ua)) return 'iPad';
  if (/Android/i.test(ua)) return 'Android';
  if (/Mac/i.test(ua)) return 'Mac';
  if (/Windows/i.test(ua)) return 'Windows';
  return 'Browser';
}

function bindEvents() {
  $('autoMode').addEventListener('click', () => setMode('auto'));
  $('oneDeviceMode').addEventListener('click', () => setMode('one'));
  $('captureButton').addEventListener('click', toggleRecognition);
  $('startButton').addEventListener('click', toggleRecognition);
  $('listenButton').addEventListener('click', () => speak($('translatedText').textContent));
  $('copyLink').addEventListener('click', copyRoomLink);
  $('refreshDevices').addEventListener('click', refreshStatus);
  $('clearHistory').addEventListener('click', clearHistory);
  $('displayMode').value = localStorage.getItem('babelfish:displayMode') || 'overlay';
  $('displayMode').addEventListener('change', (event) => {
    localStorage.setItem('babelfish:displayMode', event.target.value);
    applyOutputMode();
  });
  $('openOverlay').addEventListener('click', openOverlayWindow);
  $('copyHookCommand').addEventListener('click', copyHookCommand);
  $('sendHookText').addEventListener('click', sendDemoHookText);
  $('sourceLanguage').addEventListener('change', () => {
    updateLanguageLabels();
    if (state.listening) restartRecognition();
  });
  $('targetLanguage').addEventListener('change', updateLanguageLabels);
  $('translatorEndpoint').value = localStorage.getItem('babelfish:translatorEndpoint') || '';
  $('translatorEndpoint').addEventListener('change', (event) => {
    localStorage.setItem('babelfish:translatorEndpoint', event.target.value.trim());
  });
}

function setMode(mode) {
  $('autoMode').classList.toggle('active', mode === 'auto');
  $('oneDeviceMode').classList.toggle('active', mode === 'one');
  $('flowGuidance').textContent = mode === 'auto'
    ? 'Auto mode captures speech, translates it, shares it to every listener in the room, and can speak the result on this device.'
    : 'One-device mode captures and plays back on this device. Open the room link on another device to use it as a listener.';
}

function sourceBase() {
  return $('sourceLanguage').value.split('-')[0].toLowerCase();
}

function targetBase() {
  return $('targetLanguage').value.toLowerCase();
}

function languageLabel(code) {
  try { return languageNames.of(code.split('-')[0]) || code; } catch { return code; }
}

function updateLanguageLabels() {
  $('sourceName').textContent = languageLabel($('sourceLanguage').value);
  $('targetName').textContent = languageLabel($('targetLanguage').value);
}

function connectRoom() {
  state.eventSource?.close();
  state.eventSource = new EventSource(`/api/rooms/${roomId}/events`);
  state.eventSource.addEventListener('presence', (event) => {
    const data = JSON.parse(event.data);
    $('presence').textContent = `${data.devices} device${data.devices === 1 ? '' : 's'} connected`;
  });
  state.eventSource.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    showMessage(message, message.id !== state.lastSentId);
  });
  state.eventSource.addEventListener('hook', (event) => {
    if (overlayOnly) return;
    const hook = JSON.parse(event.data);
    state.hookQueue = state.hookQueue.then(() => handleHookText(hook));
  });
  state.eventSource.onerror = () => {
    $('presence').textContent = 'reconnecting...';
  };
}

async function refreshStatus() {
  const response = await fetch(`/api/rooms/${roomId}/status`);
  const data = await response.json();
  $('presence').textContent = `${data.devices} device${data.devices === 1 ? '' : 's'} connected`;
  toast('Devices refreshed');
}

async function toggleRecognition() {
  if (state.listening) {
    stopRecognition();
  } else {
    await startRecognition();
  }
}

async function startRecognition() {
  if (!SpeechRecognition) return;
  try {
    await startMeter();
  } catch {
    toast('Microphone meter unavailable, but speech capture may still work.');
  }
  const recognition = new SpeechRecognition();
  recognition.lang = $('sourceLanguage').value;
  recognition.continuous = true;
  recognition.interimResults = true;

  recognition.onstart = () => {
    state.listening = true;
    $('startButton').textContent = 'Stop';
    $('startButton').classList.add('recording');
    $('captureButton').textContent = 'Stop mic';
    $('captureButton').classList.add('recording');
    $('roomState').textContent = 'listening';
  };

  recognition.onresult = async (event) => {
    let transcript = '';
    let isFinal = false;
    for (let i = event.resultIndex; i < event.results.length; i += 1) {
      transcript += event.results[i][0].transcript;
      isFinal = event.results[i].isFinal || isFinal;
    }
    transcript = transcript.trim();
    if (!transcript) return;
    $('sourceText').textContent = transcript;
    $('roomState').textContent = isFinal ? 'final' : 'hearing';
    if (isFinal || transcript.length > 12) {
      const translatedText = await translate(transcript);
      await publishMessage({ sourceText: transcript, translatedText, isFinal, channel: 'speech', displayMode: currentDisplayMode() });
      if (isFinal) speak(translatedText);
    }
  };

  recognition.onerror = (event) => toast(`Mic error: ${event.error}`);
  recognition.onend = () => {
    if (state.listening) {
      recognition.start();
      return;
    }
    resetRecordingButtons();
  };
  state.recognition = recognition;
  recognition.start();
}

function stopRecognition() {
  state.listening = false;
  state.recognition?.stop();
  state.mediaStream?.getTracks().forEach(track => track.stop());
  state.mediaStream = null;
  if (state.meterFrame) cancelAnimationFrame(state.meterFrame);
  $('levelBar').style.width = '1%';
  $('roomState').textContent = 'quiet';
  resetRecordingButtons();
}

function restartRecognition() {
  stopRecognition();
  setTimeout(startRecognition, 250);
}

function resetRecordingButtons() {
  $('startButton').textContent = 'Start';
  $('startButton').classList.remove('recording');
  $('captureButton').textContent = 'Capture mic';
  $('captureButton').classList.remove('recording');
}

async function startMeter() {
  state.mediaStream = await navigator.mediaDevices.getUserMedia({ audio: true });
  state.audioContext = state.audioContext || new AudioContext();
  const source = state.audioContext.createMediaStreamSource(state.mediaStream);
  state.analyser = state.audioContext.createAnalyser();
  state.analyser.fftSize = 256;
  source.connect(state.analyser);
  const data = new Uint8Array(state.analyser.frequencyBinCount);
  const tick = () => {
    state.analyser.getByteFrequencyData(data);
    const level = data.reduce((sum, value) => sum + value, 0) / data.length;
    $('levelBar').style.width = `${Math.min(100, Math.max(1, level * 1.8))}%`;
    if (state.listening) state.meterFrame = requestAnimationFrame(tick);
  };
  tick();
}

async function translate(text) {
  const from = sourceBase();
  const to = targetBase();
  if (from === to) return text;

  const endpoint = $('translatorEndpoint').value.trim();
  if (endpoint) {
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ q: text, source: from, target: to, format: 'text' })
      });
      if (response.ok) {
        const data = await response.json();
        if (data.translatedText) return data.translatedText;
      }
    } catch (error) {
      toast(`Translator endpoint failed: ${error.message}`);
    }
  }

  if ('Translator' in self && self.Translator?.create) {
    try {
      const translator = await self.Translator.create({ sourceLanguage: from, targetLanguage: to });
      return await translator.translate(text);
    } catch {
      // Fall through to phrasebook.
    }
  }

  const normalized = text.trim().toLowerCase().replace(/[?.!]+$/g, '');
  return phrasebook.get(`${from}|${to}|${normalized}`) || `[${languageLabel(to)}] ${text}`;
}

async function publishMessage(message) {
  const payload = {
    ...message,
    sourceLanguage: sourceBase(),
    targetLanguage: targetBase(),
    displayMode: message.displayMode || currentDisplayMode(),
    channel: message.channel || 'speech'
  };
  const response = await fetch(`/api/rooms/${roomId}/messages`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(payload)
  });
  const data = await response.json();
  state.lastSentId = data.message?.id;
}

function showMessage(message, fromRemote = false) {
  $('sourceText').textContent = message.sourceText || '—';
  $('translatedText').textContent = message.translatedText || '—';
  $('sourceName').textContent = languageLabel(message.sourceLanguage || sourceBase());
  $('targetName').textContent = languageLabel(message.targetLanguage || targetBase());
  $('roomState').textContent = message.isFinal ? 'translated' : 'live';
  updateGameOutput(message);
  addHistory(message);
  if (fromRemote && $('listenButton').classList.contains('active')) speak(message.translatedText);
}


function configureOverlayMode() {
  document.body.classList.toggle('overlay-only', overlayOnly);
  applyOutputMode();
  if (overlayOnly) toast('Overlay window connected. Keep it above the game window.');
}

function currentDisplayMode() {
  return $('displayMode')?.value || localStorage.getItem('babelfish:displayMode') || 'overlay';
}

function applyOutputMode() {
  document.body.dataset.displayMode = currentDisplayMode();
}

function openOverlayWindow() {
  const url = new URL(window.location.href);
  url.searchParams.set('room', roomId);
  url.searchParams.set('overlay', '1');
  state.overlayWindow = window.open(url.toString(), 'babelfish-game-overlay', 'popup=yes,width=760,height=220');
  toast(state.overlayWindow ? 'Overlay window opened' : 'Allow pop-ups to open the overlay window');
}

async function copyHookCommand() {
  const endpoint = `${window.location.origin}/api/rooms/${roomId}/hook`;
  const body = JSON.stringify({ text: 'ゲームのテキスト', sourceLanguage: sourceBase(), targetLanguage: targetBase(), displayMode: currentDisplayMode() });
  const command = `curl -X POST ${endpoint} -H "content-type: application/json" -d '${body}'`;
  await navigator.clipboard.writeText(command);
  toast('Hook bridge POST command copied');
}

async function sendDemoHookText() {
  const text = $('hookInput').value.trim();
  if (!text) {
    toast('Add test game text first');
    return;
  }
  const response = await fetch(`/api/rooms/${roomId}/hook`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      text,
      sourceLanguage: sourceBase(),
      targetLanguage: targetBase(),
      displayMode: currentDisplayMode(),
      processName: 'demo-game.exe'
    })
  });
  if (!response.ok) toast('Could not send hook text');
}

async function handleHookText(hook) {
  $('hookState').textContent = hook.processName ? `hooked ${hook.processName}` : 'hook text received';
  const requestedTarget = hook.targetLanguage || targetBase();
  if (hook.sourceLanguage && hook.sourceLanguage !== 'auto') {
    const matchingSource = [...$('sourceLanguage').options].find(option => option.value.toLowerCase().startsWith(hook.sourceLanguage.toLowerCase()));
    if (matchingSource) $('sourceLanguage').value = matchingSource.value;
  }
  if (requestedTarget) $('targetLanguage').value = requestedTarget;
  updateLanguageLabels();
  const translatedText = await translate(hook.sourceText);
  await publishMessage({
    sourceText: hook.sourceText,
    translatedText,
    isFinal: true,
    channel: 'game-hook',
    displayMode: hook.displayMode || currentDisplayMode()
  });
}

function updateGameOutput(message) {
  const displayMode = message.displayMode || currentDisplayMode();
  const translated = message.translatedText || '—';
  const source = message.sourceText || '—';
  $('gameOriginal').textContent = source;
  $('gameTranslation').textContent = translated;
  $('overlayText').textContent = translated;
  $('overlayMeta').textContent = `${message.channel === 'game-hook' ? 'Game hook' : 'Live translation'} · ${languageLabel(message.sourceLanguage || sourceBase())} → ${languageLabel(message.targetLanguage || targetBase())}`;
  document.body.dataset.lastChannel = message.channel || 'speech';
  document.body.dataset.displayMode = displayMode;
}

function speak(text) {
  if (!text || !synth) return;
  synth.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = targetBase();
  utterance.onstart = () => {
    state.speaking = true;
    $('listenButton').classList.add('active');
  };
  utterance.onend = () => {
    state.speaking = false;
    $('listenButton').classList.remove('active');
  };
  synth.speak(utterance);
}

async function copyRoomLink() {
  const url = new URL(window.location.href);
  url.searchParams.set('room', roomId);
  await navigator.clipboard.writeText(url.toString());
  toast('Room link copied');
}

function addHistory(message) {
  if (!message.sourceText && !message.translatedText) return;
  state.history = [message, ...state.history.filter(item => item.id !== message.id)].slice(0, 12);
  localStorage.setItem(`babelfish:${roomId}:history`, JSON.stringify(state.history));
  renderHistory();
}

function renderHistory() {
  $('historyList').innerHTML = state.history.map(item => `
    <li>
      <small>${new Date(item.createdAt || Date.now()).toLocaleTimeString()} · ${languageLabel(item.sourceLanguage || 'auto')} → ${languageLabel(item.targetLanguage || 'en')}</small>
      <p>${escapeHtml(item.sourceText || '')}</p>
      <p><strong>${escapeHtml(item.translatedText || '')}</strong></p>
    </li>
  `).join('') || '<li><small>No translations yet</small><p>Start the mic to create live captions.</p></li>';
}

function clearHistory() {
  state.history = [];
  localStorage.removeItem(`babelfish:${roomId}:history`);
  renderHistory();
}

function escapeHtml(value) {
  return String(value).replace(/[&<>'"]/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;'
  }[char]));
}

function toast(message) {
  $('toast').textContent = message;
  $('toast').classList.add('show');
  clearTimeout(state.toastTimer);
  state.toastTimer = setTimeout(() => $('toast').classList.remove('show'), 2800);
}

init();
