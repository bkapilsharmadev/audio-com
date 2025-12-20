# Deployment Guide (AWS / DigitalOcean)

This project runs two services:

- **AudioCom Node server** (Express + WebSocket)
  - Serves the web UI from `/public`
  - Provides API endpoints like `/api/livekit/token`
  - Hosts WebSockets:
    - Chat: `wss://<your-domain>/ws`
    - LiveKit signaling proxy: `wss://<your-domain>/livekit/*` (proxied to LiveKit `:7880`)
- **LiveKit SFU** (media server)
  - Signaling: `:7880` (HTTP/WebSocket)
  - RTC over TCP: `:7881`
  - RTC over UDP: `:7882/udp`

The Node server **proxies LiveKit signaling** through `/livekit` so browsers can use a single origin over HTTPS. **Media still flows directly to LiveKit** on `7881`/`7882`, so those ports must be reachable from clients.

---

## What you need

- A Linux VM (Ubuntu 22.04/24.04 recommended)
- A domain (recommended) pointing to the VM’s public IP
- Docker + Docker Compose (for LiveKit, and optionally the Node server)
- Open inbound network access for:
  - `80/tcp` and `443/tcp` (for HTTPS via reverse proxy)
  - `7881/tcp` (LiveKit RTC over TCP)
  - `7882/udp` (LiveKit RTC over UDP)

Optional / only if you expose these directly (not recommended):
- `3000/tcp` (Node app)
- `7880/tcp` (LiveKit signaling)

---

## Important configuration notes (read this first)

### 1) LiveKit API key/secret must match
Your [livekit.conf](livekit.conf) contains:

```yaml
keys:
  devkey: secret
```

Your Node server defaults to these values if not provided, but for production you should set real secrets:

- `LIVEKIT_API_KEY`
- `LIVEKIT_API_SECRET`

…and also update `livekit.conf` to match.

### 2) LiveKit `--node-ip` in `docker-compose.yml`
Your current [docker-compose.yml](docker-compose.yml) starts LiveKit with:

```yaml
command: --config /etc/livekit/livekit.conf --node-ip ${LIVEKIT_NODE_IP:-139.59.28.92}
```

In cloud hosting, this **must not** be your home LAN IP. Use the VM’s public IPv4 (or an address LiveKit should advertise for ICE candidates).

On a server with a public IP, set it to that public IP. You can do this by exporting `LIVEKIT_NODE_IP` (recommended) or by editing `docker-compose.yml`.

If ICE candidates are wrong, clients will connect to signaling but audio will fail.

### 3) HTTPS termination strategy (recommended)
The Node server has a built-in HTTPS mode (`HTTPS=true`) that expects `cert/server.key` and `cert/server.cert` on disk. On servers, the usual approach is:

- Run Node **HTTP-only** (`HTTPS` unset / not `true`)
- Put **Nginx** in front to terminate TLS (Let’s Encrypt)
- Ensure Nginx forwards `X-Forwarded-Proto` so `/api/livekit/token` returns `wss://...` URLs

This guide follows that approach.

---

## Option A (recommended): Nginx + Let’s Encrypt + Node (systemd) + LiveKit (Docker)

These steps work on both AWS EC2 and DigitalOcean Droplets.

### 1) Provision the VM

- Ubuntu 22.04+ recommended
- Allocate a **static public IP**
  - AWS: Elastic IP
  - DigitalOcean: Reserved IP (optional but recommended)

Point DNS:
- `A` record: `voice.example.com` → VM public IP

### 2) Install packages

```bash
sudo apt-get update
sudo apt-get install -y \
  ca-certificates curl git ufw \
  nginx certbot python3-certbot-nginx
```

Install Docker + Compose plugin:

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# log out / in, then:
docker version
docker compose version
```

### 3) Deploy the code

```bash
sudo mkdir -p /opt/audiocom
sudo chown -R $USER:$USER /opt/audiocom
cd /opt/audiocom

git clone <YOUR_REPO_URL> .
```

### 4) Configure environment variables

Create `.env`:

```bash
cd /opt/audiocom
cat > .env <<'EOF'
PORT=3000
HOST=0.0.0.0

# Keep HTTPS off when behind Nginx
HTTPS=false

# Match livekit.conf
LIVEKIT_API_KEY=<your_key>
LIVEKIT_API_SECRET=<your_secret>

# Node -> LiveKit (inside the VM)
LIVEKIT_INTERNAL_URL=http://127.0.0.1:7880
EOF
```

### 5) Configure LiveKit

Edit [docker-compose.yml](docker-compose.yml) and set the correct `--node-ip`.

- Set `LIVEKIT_NODE_IP` to your VM public IPv4 (recommended)

Then start LiveKit:

```bash
docker compose up -d

docker ps
```

### 6) Run the Node server with systemd

Install Node 18+ (one common approach is NodeSource):

```bash
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs
node -v
npm -v
```

Install dependencies:

```bash
cd /opt/audiocom
npm ci --only=production
```

Create a systemd unit:

```bash
sudo tee /etc/systemd/system/audiocom.service >/dev/null <<'EOF'
[Unit]
Description=AudioCom Node Server
After=network.target docker.service
Wants=docker.service

[Service]
Type=simple
WorkingDirectory=/opt/audiocom
EnvironmentFile=/opt/audiocom/.env
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3

# Hardening (safe defaults)
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now audiocom
sudo systemctl status audiocom --no-pager
```

### 7) Configure Nginx (HTTP → HTTPS, WebSockets)

Create an Nginx site config:

```bash
sudo tee /etc/nginx/sites-available/audiocom >/dev/null <<'EOF'
map $http_upgrade $connection_upgrade {
  default upgrade;
  '' close;
}

server {
  listen 80;
  server_name voice.example.com;

  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # WebSocket upgrade
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
  }
}
EOF

sudo ln -sf /etc/nginx/sites-available/audiocom /etc/nginx/sites-enabled/audiocom
sudo nginx -t
sudo systemctl reload nginx
```

Issue TLS cert:

```bash
sudo certbot --nginx -d voice.example.com
```

### 8) Open firewall ports

#### UFW on the VM (optional but recommended)

```bash
sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw allow 7881/tcp
sudo ufw allow 7882/udp
sudo ufw enable
sudo ufw status
```

Also ensure your cloud firewall / security group allows the same ports (see AWS/DO sections below).

### 9) Verify

- App UI: `https://voice.example.com/`
- Health: `https://voice.example.com/api/health`
- LiveKit signaling via proxy should be reachable from the browser at: `wss://voice.example.com/livekit/rtc`

If the UI loads but audio doesn’t connect:
- Re-check LiveKit `--node-ip` and cloud firewall for `7881/tcp` + `7882/udp`.

---

## AWS (EC2) specifics

### Recommended instance
- Ubuntu 22.04 LTS
- `t3.small` or bigger for initial testing (voice load varies a lot)

### Security Group inbound rules
Allow:

- `22/tcp` from your IP (SSH)
- `80/tcp` from `0.0.0.0/0` (Let’s Encrypt + redirect)
- `443/tcp` from `0.0.0.0/0` (HTTPS)
- `7881/tcp` from `0.0.0.0/0` (LiveKit RTC TCP)
- `7882/udp` from `0.0.0.0/0` (LiveKit RTC UDP)

Do **not** expose `3000` or `7880` publicly if you’re using Nginx.

### Elastic IP
Attach an Elastic IP so your DNS does not break if the instance restarts.

---

## DigitalOcean (Droplet) specifics

### Recommended Droplet
- Ubuntu 22.04/24.04
- Basic → Regular CPU

### DigitalOcean Cloud Firewall
Inbound:

- SSH `22/tcp` from your IP
- HTTP `80/tcp` from all
- HTTPS `443/tcp` from all
- LiveKit `7881/tcp` from all
- LiveKit `7882/udp` from all

Attach the firewall to the Droplet.

---

## Option B: Run everything in Docker (advanced / optional)

You can containerize the Node server using the project [Dockerfile](Dockerfile). This avoids installing Node on the VM.

Typical approach:
- Keep Nginx on the host for TLS
- Run both LiveKit + Node via `docker compose`

If you want, tell me whether you prefer this approach and I can add a production `docker-compose.prod.yml` to the repo and document it.

---

## Troubleshooting

### Mixed content / WSS issues
- Ensure you are accessing the app over `https://`.
- Ensure Nginx forwards `X-Forwarded-Proto`.
- Ensure WebSocket upgrade headers are present.

### UI works but no audio
Most common causes:
- LiveKit `--node-ip` is wrong (advertises a private/LAN IP)
- Firewall blocks `7882/udp` (UDP is required for best performance)
- Firewall blocks `7881/tcp` (fallback transport)

### Checking logs

- Node logs:
  - `sudo journalctl -u audiocom -f`
- LiveKit logs:
  - `docker logs -f livekit`
