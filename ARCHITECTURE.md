# AudioCom Architecture & Deployment (Production)

This document describes how AudioCom is wired together and the exact production deployment sequence we’ve been implementing (Ubuntu/DigitalOcean style).

## System overview

AudioCom is a small web app + signaling layer that uses LiveKit as the SFU (media server).

- The browser loads the UI from the Node server.
- The browser uses **two WebSocket connections** to the Node server:
  - `wss://<domain>/ws` for app events/chat/speaking state.
  - `wss://<domain>/livekit/...` for **LiveKit signaling**, proxied through Node.
- The browser sends/receives **media** directly to/from the LiveKit container on UDP/TCP ports.
- coturn provides STUN/TURN ICE servers for NAT traversal (clients try STUN first, then TURN when needed).

## Components

### 1) Browser client (WebRTC audio)
- Loads the app from `https://<domain>/`.
- Requests a LiveKit token from Node (`POST /api/livekit/token`).
- Establishes:
  - A WebSocket to Node at `/ws` (app messaging).
  - A WebSocket to Node at `/livekit/...` (LiveKit signaling via proxy).
- Sends audio media to LiveKit (not to Node).

### 2) Nginx (TLS + reverse proxy)
- Terminates TLS (Let’s Encrypt).
- Proxies all HTTPS traffic to Node on `http://127.0.0.1:3000`.
- Must support **WebSocket upgrade** so `/ws` and `/livekit` stay connected.

### 3) Node server (Express + WS + LiveKit signaling proxy)
Source: `server.js`

Responsibilities:
- Serves static UI from `public/`.
- Provides REST APIs including `POST /api/livekit/token`.
- Hosts an app WebSocket at `/ws`.
- Proxies LiveKit signaling at `/livekit/*` to the internal LiveKit endpoint (`LIVEKIT_INTERNAL_URL`, usually `http://127.0.0.1:7880`).

Important implementation detail:
- Node uses a single HTTP server and manually routes upgrade requests:
  - `/ws` upgrades go to the app WebSocket server.
  - `/livekit/*` upgrades go to the LiveKit proxy.

### 4) LiveKit (SFU)
- Runs as a Docker container via `docker-compose.yml`.
- Listens on:
  - `7880/tcp` signaling (HTTP/WebSocket)
  - `7881/tcp` RTC over TCP (fallback)
  - `7882/udp` RTC over UDP (best performance)
- Must be started with `--node-ip <PUBLIC_IP>` so ICE candidates contain the correct public address.

### 5) coturn (STUN + TURN)
- Runs as a native service on the droplet (systemd) in the current deployment.
- Provides ICE servers to clients:
  - STUN on `3478/udp`
  - TURN on `3478/udp` and `3478/tcp`
  - (Optional) TURN-TLS on `5349/tcp`

## Network & ports

### Public inbound ports (required)

| Purpose | Port | Protocol | Where |
|---|---:|---|---|
| HTTPS web app + WebSockets | 443 | TCP | Nginx |
| HTTP (redirect to HTTPS) | 80 | TCP | Nginx |
| LiveKit RTC (best) | 7882 | UDP | LiveKit container |
| LiveKit RTC (fallback) | 7881 | TCP | LiveKit container |
| STUN/TURN | 3478 | UDP/TCP | coturn |

### Optional ports

| Purpose | Port | Protocol | Notes |
|---|---:|---|---|
| TURN over TLS | 5349 | TCP | Useful on restrictive networks |
| LiveKit signaling direct | 7880 | TCP | Not required publicly if using Node proxy |
| Node direct | 3000 | TCP | Not required publicly if using Nginx |

## Request / connection flows

### A) Page load
1. Browser → Nginx: `GET /`
2. Nginx → Node: `http://127.0.0.1:3000/`
3. Node serves the UI.

### B) App WebSocket (`/ws`)
1. Browser connects: `wss://<domain>/ws`
2. Nginx upgrades and proxies to Node.
3. Node handles `/ws` in its WebSocket server.

### C) LiveKit token + signaling (`/livekit/*`)
1. Browser calls Node: `POST https://<domain>/api/livekit/token`
2. Node returns:
   - JWT token
   - `url: wss://<domain>/livekit`

3. Browser connects to LiveKit signaling through Node proxy:
   - `wss://<domain>/livekit/rtc?access_token=...`
4. Node forwards `/livekit/*` to LiveKit internally (`http://127.0.0.1:7880`).

### D) Media path
- After signaling, WebRTC media flows **directly** between the browser and LiveKit:
  - UDP to `<public-ip>:7882`
  - TCP fallback to `<public-ip>:7881`
- Node is not on the media path.

### E) STUN vs TURN behavior
- Clients try STUN first to discover their public address and attempt a direct connection.
- If direct fails (strict NAT/firewall), the client automatically falls back to TURN and relays via coturn.

## Production deployment sequence (step-by-step)

These steps match the production setup we’ve been implementing:

### 1) Install baseline packages
- `nginx`
- `certbot` + Nginx plugin
- Docker + Docker Compose plugin
- Node.js 18+
- coturn

### 2) DNS
- Create an `A` record: `voice.<your-domain>` → droplet public IP.

### 3) TLS (Nginx + Certbot)
- Configure Nginx for the domain.
- Obtain a Let’s Encrypt certificate using certbot.

Critical: your HTTPS (443) server block must **not** redirect to itself.
- Only the port 80 block should redirect to HTTPS.

### 4) coturn (native)
- Configure `/etc/turnserver.conf`:
  - `listening-port=3478`
  - `listening-ip=0.0.0.0`
  - `external-ip=<PUBLIC_IP>`
  - `realm=audio-com`
  - `lt-cred-mech`
  - Add either:
    - static users (`user=<username>:<password>`) OR
    - shared secret (`static-auth-secret=...`) if your LiveKit version supports it.

### 5) LiveKit (Docker)
- Ensure `docker-compose.yml` runs LiveKit with the public node IP:
  - `--node-ip ${LIVEKIT_NODE_IP:-<PUBLIC_IP>}`
- Start:
  - `docker compose up -d`

### 6) LiveKit ICE server advertisement
- Configure `livekit.conf` to advertise STUN/TURN servers to clients.

Important compatibility note:
- Some LiveKit versions accept TURN entries with `username` + `credential`.
- Some versions also support a shared-secret field for dynamic TURN credentials.
- If LiveKit logs show: `field secret not found in type config.TURNServer`, switch to `username` + `credential`.

### 7) Node server (systemd)
- Run Node behind Nginx (keep `HTTPS=false` in `.env`).
- Ensure `.env` sets `LIVEKIT_INTERNAL_URL=http://127.0.0.1:7880`.

### 8) Verify end-to-end
- `curl https://<domain>/api/health`
- `curl -X POST https://<domain>/api/livekit/token ...`
- Browser connects:
  - `/ws` stays connected
  - `/livekit/*` stays connected
- LiveKit is reachable internally:
  - `curl http://127.0.0.1:7880/`

## Common failure modes we hit (and how to fix)

### 1) Nginx returns 301 for API endpoints
Symptom:
- `curl https://<domain>/api/health` returns an HTML 301.

Cause:
- A redirect rule inside the 443 server block (redirect loop or path normalization).

Fix:
- Keep redirect only in the 80 block:
  - `return 301 https://$host$request_uri;`
- Remove redirects from the 443 block.

### 2) Browser WebSockets close with code 1006
Symptom:
- `/ws` and/or `/livekit` disconnect immediately.

Causes:
- Missing WebSocket upgrade headers in Nginx.
- Node routing bug (sending `/ws` to the LiveKit proxy).

Fix:
- Nginx must set:
  - `proxy_http_version 1.1`
  - `proxy_set_header Upgrade $http_upgrade`
  - `proxy_set_header Connection $connection_upgrade`
  - `proxy_set_header X-Forwarded-Proto $scheme`

### 3) LiveKit keeps restarting
Symptom:
- `docker compose ps` shows LiveKit restarting.

Fix:
- Check logs: `docker compose logs --tail=200 livekit`
- If config parse errors: fix `livekit.conf` YAML keys.

### 4) LiveKit logs: could not resolve external IP
Symptom:
- `could not validate RTC config: could not resolve external IP: context deadline exceeded`

Cause:
- External IP auto-discovery timing out from inside container.

Fix:
- Prefer explicitly setting `--node-ip <PUBLIC_IP>` (already used by this project).
- Avoid forcing external IP discovery.

## Why coturn native vs Docker (in this deployment)

TURN is unusually sensitive to networking details:
- heavy UDP usage
- relay port ranges
- correct public IP advertisement

Docker can work, but you must correctly publish a relay port range and ensure correct external IP mapping. Native coturn on the host is often simpler operationally for a single droplet deployment.

## Secrets & hygiene

- Do not commit real production secrets.
- Rotate:
  - LiveKit API secret(s)
  - TURN credentials / shared secret
- Prefer keeping production secrets only on the droplet (e.g., in `/opt/audiocom/audio-com/.env` and `/etc/turnserver.conf`).
