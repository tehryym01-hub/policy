import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = process.env.PORT || 3000;

const indexHtml = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const privacyHtml = fs.readFileSync(path.join(__dirname, 'privacy_policy.html'), 'utf8');

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', timestamp: new Date().toISOString() }));
    return;
  }
  if (req.url === '/privacy_policy.html' || req.url === '/privacy') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end(privacyHtml);
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end(indexHtml);
});

server.listen(PORT, () => console.log(`Privacy policy running on port ${PORT}`));
