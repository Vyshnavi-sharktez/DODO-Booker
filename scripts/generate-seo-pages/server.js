/**
 * DODO SEO Generator — Local HTTP trigger server.
 *
 * Exposes a minimal HTTP API so the Admin Panel can trigger the existing
 * SEO generator (index.js) without running it manually in a terminal.
 * Nothing is reimplemented — the server simply spawns `node index.js`.
 *
 * Start:  node server.js    (or: npm run server)
 * Port :  GENERATOR_PORT env var, default 4040
 *
 * API:
 *   GET  /health    → { status: "ready" | "busy" }
 *   POST /generate  → runs `node index.js`, returns { success, output, error? }
 */

import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.GENERATOR_PORT ?? 4040);

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Content-Type': 'application/json',
};

let generationRunning = false;

function send(res, status, body) {
  res.writeHead(status, CORS_HEADERS);
  res.end(JSON.stringify(body));
}

function handleGenerate(res) {
  if (generationRunning) {
    return send(res, 409, {
      success: false,
      error: 'A generation is already in progress. Please wait.',
    });
  }

  generationRunning = true;
  console.log('\n[server] Starting generator...');

  const stdout = [];
  const stderr = [];

  // Spawn index.js in this directory — dotenv/config inside index.js loads .env
  // from the same CWD, so no env var setup is needed here.
  const child = spawn('node', ['index.js'], { cwd: __dirname });

  child.stdout.on('data', (d) => { const t = d.toString(); stdout.push(t); process.stdout.write(t); });
  child.stderr.on('data', (d) => { const t = d.toString(); stderr.push(t); process.stderr.write(t); });

  child.on('close', (code) => {
    generationRunning = false;
    console.log(`\n[server] Generator exited with code ${code}`);

    if (code === 0) {
      send(res, 200, { success: true, output: stdout.join('') });
    } else {
      send(res, 500, {
        success: false,
        output: stdout.join(''),
        error: stderr.join('') || `Process exited with code ${code}`,
        exitCode: code,
      });
    }
  });

  child.on('error', (err) => {
    generationRunning = false;
    console.error('[server] Failed to spawn generator:', err.message);
    send(res, 500, { success: false, output: '', error: err.message });
  });
}

const server = createServer((req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, CORS_HEADERS);
    return res.end();
  }

  if (req.method === 'GET' && req.url === '/health') {
    return send(res, 200, { status: generationRunning ? 'busy' : 'ready' });
  }

  if (req.method === 'POST' && req.url === '/generate') {
    return handleGenerate(res);
  }

  send(res, 404, { error: 'Not found' });
});

server.listen(PORT, () => {
  console.log('\n── DODO SEO Generator Server ───────────────────────────');
  console.log(`   Listening : http://localhost:${PORT}`);
  console.log(`   Generate  : POST http://localhost:${PORT}/generate`);
  console.log(`   Health    : GET  http://localhost:${PORT}/health`);
  console.log('────────────────────────────────────────────────────────\n');
});
