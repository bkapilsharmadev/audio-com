# AudioCom - Voice Chat with LiveKit SFU

Real-time voice chat using **LiveKit SFU** - efficient for mobile devices!

## Quick Start

**1. Start LiveKit server:**
```bash
docker-compose up -d
```

**2. Install dependencies & run:**
```bash
npm install
npm start
```

**3. Open:** http://localhost:3000

## Deployment

See [DEPLOYMENT.md](DEPLOYMENT.md) for step-by-step instructions for AWS EC2 and DigitalOcean.

For a deeper explanation of how the pieces fit together (Nginx ↔ Node ↔ LiveKit ↔ coturn), see [ARCHITECTURE.md](ARCHITECTURE.md).

## Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Client 1  │────▶│   LiveKit   │◀────│   Client 2  │
│   (Mobile)  │◀────│    SFU      │────▶│  (Desktop)  │
└─────────────┘     └─────────────┘     └─────────────┘
        │                  │                    │
        └──────────────────┼────────────────────┘
                           │
                    ┌──────▼──────┐
                    │   Node.js   │
                    │   Server    │
                    └─────────────┘
```

**Why SFU?**
- Mobile uploads audio **once** to server
- Server forwards to all participants
- Much lighter than WebRTC mesh!

## Features

| Feature | Status |
|---------|--------|
| Voice chat | ✅ LiveKit SFU |
| Group calls | ✅ Up to 100 users |
| Text chat | ✅ WebSocket |
| Mute/Deafen | ✅ M/D keys |
| Mobile | ✅ Optimized |

## Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | LiveKit server |
| `server.js` | API + token generation |
| `public/js/livekit-client.js` | LiveKit browser client |
