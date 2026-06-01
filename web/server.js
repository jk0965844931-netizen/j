#!/usr/bin/env node
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const publicDir = __dirname;
const port = Number(process.env.PORT || 4173);
const rooms = new Map();

const mimeTypes = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml; charset=utf-8',
  '.ico': 'image/x-icon'
};

function getRoom(id) {
  const safeId = String(id || '').replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 48) || 'lobby';
  if (!rooms.has(safeId)) {
    rooms.set(safeId, { clients: new Set(), lastMessage: null });
  }
  return { id: safeId, room: rooms.get(safeId) };
}

function sendEvent(client, event, payload) {
  client.write(`event: ${event}\n`);
  client.write(`data: ${JSON.stringify(payload)}\n\n`);
}

function broadcast(roomId, event, payload) {
  const { room } = getRoom(roomId);
  for (const client of room.clients) {
    sendEvent(client, event, payload);
  }
}

function json(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    'access-control-allow-origin': '*'
  });
  res.end(body);
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', chunk => {
      raw += chunk;
      if (raw.length > 64_000) {
        reject(new Error('Payload too large'));
        req.destroy();
      }
    });
    req.on('end', () => {
      try {
        resolve(raw ? JSON.parse(raw) : {});
      } catch (error) {
        reject(error);
      }
    });
    req.on('error', reject);
  });
}

function serveStatic(req, res) {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname);
  const filePath = path.normalize(path.join(publicDir, pathname));

  if (!filePath.startsWith(publicDir)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  fs.readFile(filePath, (error, data) => {
    if (error) {
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('Not found');
      return;
    }
    res.writeHead(200, {
      'content-type': mimeTypes[path.extname(filePath)] || 'application/octet-stream',
      'cache-control': filePath.endsWith('index.html') ? 'no-store' : 'public, max-age=3600'
    });
    res.end(data);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'access-control-allow-origin': '*',
      'access-control-allow-methods': 'GET,POST,OPTIONS',
      'access-control-allow-headers': 'content-type'
    });
    res.end();
    return;
  }

  const eventMatch = url.pathname.match(/^\/api\/rooms\/([^/]+)\/events$/);
  if (req.method === 'GET' && eventMatch) {
    const { id, room } = getRoom(eventMatch[1]);
    res.writeHead(200, {
      'content-type': 'text/event-stream; charset=utf-8',
      'cache-control': 'no-cache, no-transform',
      connection: 'keep-alive',
      'access-control-allow-origin': '*'
    });
    res.write(': connected\n\n');
    room.clients.add(res);
    sendEvent(res, 'presence', { room: id, devices: room.clients.size });
    if (room.lastMessage) sendEvent(res, 'message', room.lastMessage);
    broadcast(id, 'presence', { room: id, devices: room.clients.size });

    const heartbeat = setInterval(() => res.write(': heartbeat\n\n'), 25_000);
    req.on('close', () => {
      clearInterval(heartbeat);
      room.clients.delete(res);
      broadcast(id, 'presence', { room: id, devices: room.clients.size });
    });
    return;
  }

  const messageMatch = url.pathname.match(/^\/api\/rooms\/([^/]+)\/messages$/);
  if (req.method === 'POST' && messageMatch) {
    try {
      const { id, room } = getRoom(messageMatch[1]);
      const body = await readJson(req);
      const message = {
        id: crypto.randomUUID(),
        room: id,
        sourceText: String(body.sourceText || '').slice(0, 5000),
        translatedText: String(body.translatedText || '').slice(0, 5000),
        sourceLanguage: String(body.sourceLanguage || 'auto').slice(0, 20),
        targetLanguage: String(body.targetLanguage || 'en').slice(0, 20),
        isFinal: Boolean(body.isFinal),
        channel: String(body.channel || 'speech').slice(0, 32),
        displayMode: String(body.displayMode || 'app').slice(0, 32),
        createdAt: new Date().toISOString()
      };
      room.lastMessage = message;
      broadcast(id, 'message', message);
      json(res, 200, { ok: true, message });
    } catch (error) {
      json(res, 400, { ok: false, error: error.message });
    }
    return;
  }


  const hookMatch = url.pathname.match(/^\/api\/rooms\/([^/]+)\/hook$/);
  if (req.method === 'POST' && hookMatch) {
    try {
      const { id } = getRoom(hookMatch[1]);
      const body = await readJson(req);
      const hookText = String(body.text || body.sourceText || '').slice(0, 5000);
      if (!hookText.trim()) {
        json(res, 400, { ok: false, error: 'Missing hook text' });
        return;
      }
      const payload = {
        id: crypto.randomUUID(),
        room: id,
        sourceText: hookText,
        sourceLanguage: String(body.sourceLanguage || 'auto').slice(0, 20),
        targetLanguage: String(body.targetLanguage || '').slice(0, 20),
        engine: String(body.engine || 'external-hook').slice(0, 60),
        processName: String(body.processName || '').slice(0, 120),
        displayMode: String(body.displayMode || 'overlay').slice(0, 32),
        createdAt: new Date().toISOString()
      };
      broadcast(id, 'hook', payload);
      json(res, 200, { ok: true, hook: payload });
    } catch (error) {
      json(res, 400, { ok: false, error: error.message });
    }
    return;
  }

  const statusMatch = url.pathname.match(/^\/api\/rooms\/([^/]+)\/status$/);
  if (req.method === 'GET' && statusMatch) {
    const { id, room } = getRoom(statusMatch[1]);
    json(res, 200, { room: id, devices: room.clients.size, lastMessage: room.lastMessage });
    return;
  }

  if (req.method === 'GET') {
    serveStatic(req, res);
    return;
  }

  json(res, 405, { ok: false, error: 'Method not allowed' });
});

server.listen(port, () => {
  console.log(`Babelfish Live web app running at http://localhost:${port}`);
});
