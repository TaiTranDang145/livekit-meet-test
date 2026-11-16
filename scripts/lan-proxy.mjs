#!/usr/bin/env node

import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const certDir = path.resolve(
  process.env.LIVEKIT_LAN_CERT_DIR ?? path.join(projectRoot, '.local', 'lan-certs'),
);
const host = process.env.LIVEKIT_LAN_HOST ?? '0.0.0.0';
const httpsPort = Number(process.env.LIVEKIT_LAN_HTTPS_PORT ?? 3000);
const caPort = Number(process.env.LIVEKIT_LAN_CA_PORT ?? 8085);
const nextHost = process.env.NEXT_UPSTREAM_HOST ?? '127.0.0.1';
const nextPort = Number(process.env.NEXT_UPSTREAM_PORT ?? 3001);
const liveKitHost = process.env.LIVEKIT_UPSTREAM_HOST ?? '127.0.0.1';
const liveKitPort = Number(process.env.LIVEKIT_UPSTREAM_PORT ?? 7880);
const caFile = path.join(certDir, 'ca.crt');
const serverCertFile = path.join(certDir, 'server.crt');
const serverKeyFile = path.join(certDir, 'server.key');

for (const file of [caFile, serverCertFile, serverKeyFile]) {
  if (!fs.existsSync(file)) {
    console.error(`Missing LAN TLS file: ${file}`);
    console.error('Run scripts/generate-lan-certs.sh <LAN_IP> first.');
    process.exit(1);
  }
}

function upstreamForRequest(url = '') {
  return url.startsWith('/rtc')
    ? { hostname: liveKitHost, port: liveKitPort }
    : { hostname: nextHost, port: nextPort };
}

const httpsServer = https.createServer(
  {
    key: fs.readFileSync(serverKeyFile),
    cert: fs.readFileSync(serverCertFile),
  },
  (req, res) => {
    const upstream = upstreamForRequest(req.url);
    const request = http.request(
      {
        ...upstream,
        method: req.method,
        path: req.url,
        headers: {
          ...req.headers,
          host: `${upstream.hostname}:${upstream.port}`,
          'x-forwarded-proto': 'https',
        },
      },
      (upstreamRes) => {
        res.writeHead(upstreamRes.statusCode ?? 502, upstreamRes.headers);
        upstreamRes.pipe(res);
      },
    );

    request.on('error', (error) => {
      console.error(`HTTP upstream error (${upstream.port}):`, error.message);
      if (!res.headersSent) res.writeHead(502);
      res.end('Upstream unavailable');
    });
    req.pipe(request);
  },
);

httpsServer.on('upgrade', (req, clientSocket, head) => {
  const upstream = req.url?.startsWith('/_next')
    ? { hostname: nextHost, port: nextPort }
    : { hostname: liveKitHost, port: liveKitPort };
  const upstreamRequest = http.request({
    ...upstream,
    method: req.method,
    path: req.url,
    headers: { ...req.headers, host: `${upstream.hostname}:${upstream.port}` },
  });

  upstreamRequest.on('upgrade', (upstreamResponse, upstreamSocket, upstreamHead) => {
    clientSocket.write(
      `HTTP/${upstreamResponse.httpVersion} ${upstreamResponse.statusCode} ${upstreamResponse.statusMessage}\r\n`,
    );
    for (let i = 0; i < upstreamResponse.rawHeaders.length; i += 2) {
      clientSocket.write(`${upstreamResponse.rawHeaders[i]}: ${upstreamResponse.rawHeaders[i + 1]}\r\n`);
    }
    clientSocket.write('\r\n');
    if (upstreamHead.length) clientSocket.write(upstreamHead);
    if (head.length) upstreamSocket.write(head);
    upstreamSocket.pipe(clientSocket);
    clientSocket.pipe(upstreamSocket);
    clientSocket.on('error', () => upstreamSocket.destroy());
    upstreamSocket.on('error', () => clientSocket.destroy());
  });

  upstreamRequest.on('response', (upstreamResponse) => {
    clientSocket.write(
      `HTTP/${upstreamResponse.httpVersion} ${upstreamResponse.statusCode} ${upstreamResponse.statusMessage}\r\n\r\n`,
    );
    upstreamResponse.pipe(clientSocket);
  });
  upstreamRequest.on('error', (error) => {
    console.error(`WebSocket upstream error (${upstream.port}):`, error.message);
    clientSocket.destroy();
  });
  upstreamRequest.end();
});

const caServer = http.createServer((req, res) => {
  if (req.url !== '/livekit-meet-lan-ca.crt') {
    res.writeHead(404).end('Not found');
    return;
  }
  res.writeHead(200, {
    'content-type': 'application/x-x509-ca-cert',
    'content-disposition': 'attachment; filename="livekit-meet-lan-ca.crt"',
    'cache-control': 'no-store',
  });
  fs.createReadStream(caFile).pipe(res);
});

httpsServer.listen(httpsPort, host, () => {
  console.log(`HTTPS/WSS proxy listening on ${host}:${httpsPort}; certs: ${certDir}`);
});
caServer.listen(caPort, host, () => {
  console.log(`CA download listening on ${host}:${caPort}`);
});

function shutdown() {
  httpsServer.close();
  caServer.close();
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
