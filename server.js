/**
 * AudioCom Voice Server
 * Express server with LiveKit SFU integration
 */

require('dotenv').config();
const express = require('express');
const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const cors = require('cors');
const crypto = require('crypto');
const { createProxyMiddleware } = require('http-proxy-middleware');
const WebSocket = require('ws');
const { v4: uuidv4 } = require('uuid');

// LiveKit SDK for token generation
const { AccessToken } = require('livekit-server-sdk');

// Simple password hashing using crypto (no bcrypt dependency needed)
function hashPassword(password) {
    return crypto.createHash('sha256').update(password).digest('hex');
}

function verifyPassword(password, hash) {
    return hashPassword(password) === hash;
}

const app = express();
let server;
let livekitProxy;

// Initialize server with HTTPS or HTTP based on environment variable
function initializeServer() {
    if (process.env.HTTPS === 'true') {
        const certPath = path.join(__dirname, 'cert', 'server.cert');
        const keyPath = path.join(__dirname, 'cert', 'server.key');
        
        try {
            // Try to read existing certificates
            const cert = fs.readFileSync(certPath);
            const key = fs.readFileSync(keyPath);
            server = https.createServer({ key, cert }, app);
            console.log('✓ HTTPS enabled (using existing certificates)');
            return server;
        } catch (err) {
            console.error('✗ Certificate not found at cert/server.cert or cert/server.key');
            console.error('  To generate certificates on Windows, run:');
            console.error('  1. Install OpenSSL: https://slproweb.com/products/Win32OpenSSL.html');
            console.error('  2. Run: openssl req -nodes -new -x509 -keyout cert/server.key -out cert/server.cert -days 365 -subj "/C=US/ST=Local/L=Local/O=Dev/CN=localhost"');
            console.error('  3. Then set HTTPS=true and run again');
            console.error('\n  Alternatively, use HTTP mode by running without HTTPS=true');
            process.exit(1);
        }
    } else {
        server = http.createServer(app);
        return server;
    }
}

function setupGracefulShutdown(srv) {
    process.on('SIGTERM', () => {
        console.log('SIGTERM received, shutting down...');
        srv.close(() => {
            console.log('Server closed');
            process.exit(0);
        });
    });
}

function setupWebSocket(srv) {
    // Use noServer mode so we can manually route upgrades (needed for LiveKit proxy coexistence)
    const wss = new WebSocket.Server({ noServer: true });

    wss.on('connection', (ws) => {
        let userId = null;
        
        ws.on('message', (message) => {
            try {
                const data = JSON.parse(message);
                
                switch (data.type) {
                    case 'register':
                        userId = data.userId;
                        ws.userId = userId;
                        break;
                        
                    case 'speaking':
                        const user = users.get(userId);
                        if (user) {
                            user.isSpeaking = data.isSpeaking;
                            broadcastToRoom(user.roomId, {
                                type: 'user-speaking',
                                userId,
                                isSpeaking: data.isSpeaking
                            }, userId);
                        }
                        break;
                        
                    case 'join-room':
                        const joinUser = users.get(userId);
                        if (joinUser) {
                            broadcastToRoom(data.roomId, {
                                type: 'user-joined',
                                userId,
                                userName: joinUser.name
                            });
                        }
                        break;
                        
                    case 'leave-room':
                        const leaveUser = users.get(userId);
                        if (leaveUser) {
                            broadcastToRoom(data.roomId, {
                                type: 'user-left',
                                userId,
                                userName: leaveUser.name
                            });
                        }
                        break;
                    
                    case 'chat-message':
                        const chatUser = users.get(userId);
                        if (chatUser) {
                            broadcastToRoom(chatUser.roomId, {
                                type: 'chat-message',
                                userId,
                                userName: chatUser.name,
                                content: data.content,
                                timestamp: new Date().toISOString()
                            });
                        }
                        break;
                    
                    case 'webrtc-join':
                        const rtcUser = users.get(data.userId);
                        if (rtcUser) {
                            ws.userId = data.userId;
                            ws.roomId = data.roomId;
                            
                            const rtcRoom = rooms.get(data.roomId);
                            if (rtcRoom) {
                                const existingUsers = Array.from(rtcRoom.users).filter(id => id !== data.userId);
                                
                                ws.send(JSON.stringify({
                                    type: 'webrtc-existing-users',
                                    users: existingUsers
                                }));
                                
                                broadcastToRoom(data.roomId, {
                                    type: 'webrtc-user-joined',
                                    userId: data.userId
                                }, data.userId);
                            }
                        }
                        break;
                        
                    case 'webrtc-offer':
                    case 'webrtc-answer':
                    case 'webrtc-ice-candidate':
                        wss.clients.forEach(client => {
                            if (client.readyState === WebSocket.OPEN && 
                                client.userId === data.targetUserId) {
                                client.send(JSON.stringify({
                                    type: data.type,
                                    fromUserId: data.fromUserId,
                                    offer: data.offer,
                                    answer: data.answer,
                                    candidate: data.candidate
                                }));
                            }
                        });
                        break;
                        
                    case 'webrtc-leave':
                        if (ws.roomId) {
                            broadcastToRoom(ws.roomId, {
                                type: 'webrtc-user-left',
                                userId: ws.userId
                            }, ws.userId);
                        }
                        break;
                }
            } catch (e) {
                console.error('WebSocket message error:', e);
            }
        });
        
        ws.on('close', () => {
            if (userId) {
                const user = users.get(userId);
                if (user && user.roomId) {
                    broadcastToRoom(user.roomId, {
                        type: 'user-left',
                        userId,
                        userName: user.name
                    });
                    
                    const room = rooms.get(user.roomId);
                    if (room) {
                        room.users.delete(userId);
                    }
                }
                users.delete(userId);
            }
        });
    });
    
    return wss;
}

// Global reference to WebSocket server for broadcast function
let globalWss = null;

// Initialize server and setup
const srv = initializeServer();

// Configuration
const PORT = process.env.PORT || 3000;
const HOST = process.env.HOST || '0.0.0.0';

// LiveKit Configuration
let LIVEKIT_URL = process.env.LIVEKIT_URL;
if (!LIVEKIT_URL) {
    // For local development, use ws:// (not wss://) even with HTTPS on main app
    // Browsers allow mixed content (HTTPS + ws://) for localhost
    LIVEKIT_URL = 'ws://localhost:7880';
}
const LIVEKIT_API_KEY = process.env.LIVEKIT_API_KEY || 'devkey';
const LIVEKIT_API_SECRET = process.env.LIVEKIT_API_SECRET || 'secret';

// In-memory storage for rooms and users (in production, use Redis/DB)
const rooms = new Map();
const users = new Map();
const invites = new Map();

// Initialize default rooms
function initializeDefaultRooms() {
    rooms.set('lobby', {
        id: 'lobby',
        name: 'Lobby',
        description: 'Main lobby - welcome!',
        isPrivate: false,
        isPasswordProtected: false,
        password: null,
        maxUsers: 100,
        users: new Set(),
        createdAt: new Date()
    });
    
    rooms.set('general', {
        id: 'general',
        name: 'General',
        description: 'General discussion',
        isPrivate: false,
        isPasswordProtected: false,
        password: null,
        maxUsers: 50,
        users: new Set(),
        createdAt: new Date()
    });
    
    rooms.set('gaming', {
        id: 'gaming',
        name: 'Gaming',
        description: 'Voice chat for gamers',
        isPrivate: false,
        isPasswordProtected: false,
        password: null,
        maxUsers: 25,
        users: new Set(),
        createdAt: new Date()
    });
}

initializeDefaultRooms();

// Middleware
app.use(cors());
app.use(express.json());

// Proxy LiveKit through this server so HTTPS pages can use WSS without mixed-content.
// Browser connects to: wss(s)://<host>:<appPort>/livekit/rtc?... and we forward to http://127.0.0.1:7880/rtc?... inside the LAN.
livekitProxy = createProxyMiddleware({
    target: process.env.LIVEKIT_INTERNAL_URL || 'http://127.0.0.1:7880',
    changeOrigin: true,
    ws: true,
    pathRewrite: { '^/livekit': '' },
    logLevel: 'debug',
    onError: (err, req, res) => {
        console.error('❌ LiveKit proxy error:', err.message);
    },
    onProxyReq: (proxyReq, req, res) => {
        console.log('🔄 LiveKit proxy HTTP:', req.method, req.url);
    },
    onProxyReqWs: (proxyReq, req, socket, options, head) => {
        console.log('🔄 LiveKit proxy WS:', req.url);
    }
});
app.use('/livekit', livekitProxy);

app.use(express.static(path.join(__dirname, 'public')));

// API Routes
// Health check
app.get('/api/health', (req, res) => {
    res.json({ 
        status: 'ok', 
        timestamp: new Date().toISOString(),
        livekit: {
            url: LIVEKIT_URL,
            configured: !!(LIVEKIT_API_KEY && LIVEKIT_API_SECRET)
        }
    });
});

// Get server info
app.get('/api/server/info', (req, res) => {
    res.json({
        name: 'AudioCom Voice Server',
        version: '1.0.0',
        maxUsers: 200,
        currentUsers: users.size,
        totalRooms: rooms.size,
        livekitUrl: LIVEKIT_URL
    });
});

// LiveKit Token Generation
app.post('/api/livekit/token', async (req, res) => {
    const { roomId, userId, userName } = req.body;
    
    if (!roomId || !userId) {
        return res.status(400).json({ error: 'roomId and userId are required' });
    }
    
    try {
        // Create access token
        const token = new AccessToken(LIVEKIT_API_KEY, LIVEKIT_API_SECRET, {
            identity: userId,
            name: userName || userId
        });
        
        // Grant permissions for the room
        token.addGrant({
            room: roomId,
            roomJoin: true,
            canPublish: true,
            canSubscribe: true,
            canPublishData: true
        });
        
        // toJwt() might be async in some versions
        let jwt = token.toJwt();
        if (jwt instanceof Promise) {
            jwt = await jwt;
        }
        
        // Ensure jwt is a string
        const tokenString = typeof jwt === 'string' ? jwt : (jwt.token || String(jwt));
        
        console.log('✓ Generated LiveKit token for user:', userId, 'in room:', roomId);
        
        // Public URL that the browser should connect to.
        // Always point clients at this server's /livekit proxy (same-origin), to avoid mixed-content issues.
        const requestHost = req.get('host') || req.hostname;
        const isSecureConnection = req.secure || req.get('x-forwarded-proto') === 'https';
        const publicLivekitUrl = requestHost
            ? `${isSecureConnection ? 'wss' : 'ws'}://${requestHost}/livekit`
            : LIVEKIT_URL;
        
        res.json({
            token: tokenString,
            url: publicLivekitUrl,
            roomId,
            userId
        });
    } catch (error) {
        console.error('Error generating LiveKit token:', error);
        res.status(500).json({ error: 'Failed to generate token' });
    }
});

// List all rooms
app.get('/api/rooms', (req, res) => {
    const roomList = Array.from(rooms.values())
        .filter(room => !room.isPrivate)
        .map(room => ({
            id: room.id,
            name: room.name,
            description: room.description,
            userCount: room.users.size,
            maxUsers: room.maxUsers,
            isPasswordProtected: room.isPasswordProtected || false
        }));
    res.json(roomList);
});

// Get specific room
app.get('/api/rooms/:id', (req, res) => {
    const room = rooms.get(req.params.id);
    if (!room) {
        return res.status(404).json({ error: 'Room not found' });
    }
    
    const userList = Array.from(room.users).map(userId => {
        const user = users.get(userId);
        return user ? { id: user.id, name: user.name } : null;
    }).filter(Boolean);
    
    res.json({
        id: room.id,
        name: room.name,
        description: room.description,
        users: userList,
        maxUsers: room.maxUsers,
        isPrivate: room.isPrivate
    });
});

// Create new room
app.post('/api/rooms', (req, res) => {
    const { name, description, isPrivate, maxUsers, password } = req.body;
    
    if (!name || name.trim().length === 0) {
        return res.status(400).json({ error: 'Room name is required' });
    }
    
    const id = name.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
    
    if (rooms.has(id)) {
        return res.status(409).json({ error: 'Room already exists' });
    }
    
    const hasPassword = password && password.trim().length > 0;
    
    const room = {
        id,
        name: name.trim(),
        description: description || '',
        isPrivate: isPrivate || false,
        isPasswordProtected: hasPassword,
        password: hasPassword ? hashPassword(password.trim()) : null,
        maxUsers: maxUsers || 25,
        users: new Set(),
        createdAt: new Date()
    };
    
    rooms.set(id, room);
    
    console.log(`✓ Room created: ${room.name}${hasPassword ? ' (password protected)' : ''}`);
    
    res.status(201).json({
        id: room.id,
        name: room.name,
        description: room.description,
        isPrivate: room.isPrivate,
        isPasswordProtected: room.isPasswordProtected,
        maxUsers: room.maxUsers
    });
});

// Create private 1-on-1 room
app.post('/api/rooms/private', (req, res) => {
    const { userId1, userId2 } = req.body;
    
    if (!userId1 || !userId2) {
        return res.status(400).json({ error: 'Both user IDs are required' });
    }
    
    // Create unique room ID for the pair
    const sortedIds = [userId1, userId2].sort();
    const roomId = `private-${sortedIds[0]}-${sortedIds[1]}`;
    
    // Check if room already exists
    if (rooms.has(roomId)) {
        const existingRoom = rooms.get(roomId);
        return res.json({
            id: existingRoom.id,
            name: existingRoom.name,
            isPrivate: true,
            existing: true
        });
    }
    
    const user1 = users.get(userId1);
    const user2 = users.get(userId2);
    
    const room = {
        id: roomId,
        name: `Private: ${user1?.name || 'User'} & ${user2?.name || 'User'}`,
        description: 'Private conversation',
        isPrivate: true,
        maxUsers: 2,
        users: new Set(),
        allowedUsers: new Set([userId1, userId2]),
        createdAt: new Date()
    };
    
    rooms.set(roomId, room);
    
    res.status(201).json({
        id: room.id,
        name: room.name,
        isPrivate: true,
        existing: false
    });
});

// Delete room
app.delete('/api/rooms/:id', (req, res) => {
    const room = rooms.get(req.params.id);
    
    if (!room) {
        return res.status(404).json({ error: 'Room not found' });
    }
    
    // Don't allow deleting default rooms
    if (['lobby', 'general', 'gaming'].includes(req.params.id)) {
        return res.status(403).json({ error: 'Cannot delete default rooms' });
    }
    
    rooms.delete(req.params.id);
    res.json({ success: true, message: 'Room deleted' });
});

// List all users
app.get('/api/users', (req, res) => {
    const { roomId } = req.query;
    
    let userList = Array.from(users.values());
    
    // Filter by roomId if provided, otherwise only return users who have joined a room
    if (roomId) {
        userList = userList.filter(user => user.roomId === roomId);
    } else {
        // Only return users who are in a room (not just registered)
        userList = userList.filter(user => user.roomId);
    }
    
    const result = userList.map(user => ({
        id: user.id,
        name: user.name,
        roomId: user.roomId,
        isMuted: user.isMuted,
        isDeafened: user.isDeafened,
        isSpeaking: user.isSpeaking,
        connectedAt: user.connectedAt
    }));
    res.json(result);
});

// Get specific user
app.get('/api/users/:id', (req, res) => {
    const user = users.get(req.params.id);
    if (!user) {
        return res.status(404).json({ error: 'User not found' });
    }
    res.json({
        id: user.id,
        name: user.name,
        roomId: user.roomId,
        isMuted: user.isMuted,
        isDeafened: user.isDeafened
    });
});

// Register user
app.post('/api/users/register', (req, res) => {
    const { name } = req.body;
    
    if (!name || name.trim().length === 0) {
        return res.status(400).json({ error: 'Username is required' });
    }
    
    // Check for duplicate names
    const existingUser = Array.from(users.values()).find(u => u.name.toLowerCase() === name.toLowerCase());
    if (existingUser) {
        return res.status(409).json({ error: 'Username already taken' });
    }
    
    const user = {
        id: uuidv4(),
        name: name.trim(),
        roomId: null,  // No default room - user must select one
        isMuted: false,
        isDeafened: false,
        isSpeaking: false,
        connectedAt: new Date()
    };
    
    users.set(user.id, user);
    
    // Don't auto-add to lobby - user must select a channel
    
    res.status(201).json({
        id: user.id,
        name: user.name,
        roomId: user.roomId,
        token: uuidv4() // Simple token for session
    });
});

// Check if room requires password
app.get('/api/rooms/:roomId/requires-password', (req, res) => {
    const room = rooms.get(req.params.roomId);
    if (!room) {
        return res.status(404).json({ error: 'Room not found' });
    }
    res.json({
        requiresPassword: room.isPasswordProtected || false,
        roomName: room.name
    });
});

// User joins room
app.post('/api/users/:userId/join/:roomId', (req, res) => {
    const { userId, roomId } = req.params;
    const { password } = req.body || {};
    
    const user = users.get(userId);
    if (!user) {
        return res.status(404).json({ error: 'User not found' });
    }
    
    const room = rooms.get(roomId);
    if (!room) {
        return res.status(404).json({ error: 'Room not found' });
    }
    
    // Check if room is full
    if (room.users.size >= room.maxUsers) {
        return res.status(403).json({ error: 'Room is full' });
    }
    
    // Check private room access
    if (room.isPrivate && room.allowedUsers && !room.allowedUsers.has(userId)) {
        return res.status(403).json({ error: 'Access denied to private room' });
    }
    
    // Check password if room is protected
    if (room.isPasswordProtected) {
        if (!password) {
            return res.status(401).json({ 
                error: 'Password required',
                requiresPassword: true,
                roomName: room.name
            });
        }
        
        if (!verifyPassword(password, room.password)) {
            return res.status(401).json({ error: 'Incorrect password' });
        }
    }
    
    const previousRoomId = user.roomId;
    
    // Remove from current room and notify
    if (previousRoomId) {
        const currentRoom = rooms.get(previousRoomId);
        if (currentRoom) {
            currentRoom.users.delete(userId);
            // Broadcast to users in previous room that this user left
            broadcastToRoom(previousRoomId, {
                type: 'user-left',
                userId,
                userName: user.name
            });
        }
    }
    
    // Join new room
    room.users.add(userId);
    user.roomId = roomId;
    
    // Broadcast to users in new room that this user joined
    broadcastToRoom(roomId, {
        type: 'user-joined',
        userId,
        userName: user.name,
        user: {
            id: user.id,
            name: user.name,
            isMuted: user.isMuted,
            isDeafened: user.isDeafened,
            isSpeaking: user.isSpeaking
        }
    }, userId);  // Exclude the joining user from receiving this
    
    res.json({
        success: true,
        roomId: room.id,
        roomName: room.name
    });
});

// User leaves (disconnect)
app.post('/api/users/:userId/leave', (req, res) => {
    const { userId } = req.params;
    
    const user = users.get(userId);
    if (!user) {
        return res.status(404).json({ error: 'User not found' });
    }
    
    // Remove from current room
    if (user.roomId) {
        const room = rooms.get(user.roomId);
        if (room) {
            room.users.delete(userId);
        }
    }
    
    users.delete(userId);
    
    res.json({ success: true, message: 'User disconnected' });
});

// Update user state (mute, deafen)
app.patch('/api/users/:userId/state', (req, res) => {
    const { userId } = req.params;
    const { isMuted, isDeafened, isSpeaking } = req.body;
    
    const user = users.get(userId);
    if (!user) {
        return res.status(404).json({ error: 'User not found' });
    }
    
    if (typeof isMuted === 'boolean') user.isMuted = isMuted;
    if (typeof isDeafened === 'boolean') user.isDeafened = isDeafened;
    if (typeof isSpeaking === 'boolean') user.isSpeaking = isSpeaking;
    
    // Broadcast state change to all users in the same room
    if (user.roomId) {
        broadcastToRoom(user.roomId, {
            type: 'user-state-changed',
            userId: user.id,
            isMuted: user.isMuted,
            isDeafened: user.isDeafened,
            isSpeaking: user.isSpeaking
        });
    }
    
    res.json({
        id: user.id,
        isMuted: user.isMuted,
        isDeafened: user.isDeafened,
        isSpeaking: user.isSpeaking
    });
});

// Create invite link
app.post('/api/invite', (req, res) => {
    const { roomId, expiresIn } = req.body;
    
    const room = rooms.get(roomId);
    if (!room) {
        return res.status(404).json({ error: 'Room not found' });
    }
    
    const inviteCode = uuidv4().split('-')[0];
    const expiresAt = new Date(Date.now() + (expiresIn || 24 * 60 * 60 * 1000)); // Default 24h
    
    invites.set(inviteCode, {
        roomId,
        expiresAt,
        createdAt: new Date()
    });
    
    res.json({
        inviteCode,
        roomId,
        roomName: room.name,
        expiresAt,
        link: `${req.protocol}://${req.get('host')}/?invite=${inviteCode}`
    });
});

// Use invite
app.get('/api/invite/:code', (req, res) => {
    const invite = invites.get(req.params.code);
    
    if (!invite) {
        return res.status(404).json({ error: 'Invite not found' });
    }
    
    if (new Date() > invite.expiresAt) {
        invites.delete(req.params.code);
        return res.status(410).json({ error: 'Invite has expired' });
    }
    
    const room = rooms.get(invite.roomId);
    
    res.json({
        roomId: invite.roomId,
        roomName: room?.name || 'Unknown',
        valid: true
    });
});

// Fallback to index.html for SPA routing
app.get('*', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

function broadcastToRoom(roomId, message, excludeUserId = null) {
    if (!globalWss) return;
    
    const room = rooms.get(roomId);
    if (!room) return;
    
    globalWss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN && 
            client.userId && 
            room.users.has(client.userId) &&
            client.userId !== excludeUserId) {
            client.send(JSON.stringify(message));
        }
    });
}

// Start server
if (srv) {
    const PORT = process.env.PORT || 3000;
    const HOST = process.env.HOST || '0.0.0.0';
    const protocol = process.env.HTTPS === 'true' ? 'HTTPS' : 'HTTP';
    
    // Create WebSocket server for chat FIRST (it will set up its own upgrade handler)
    globalWss = setupWebSocket(srv);

    // Now override the upgrade handler to route /livekit to proxy, /ws to chat WS.
    // This is critical: /ws must NEVER be forwarded to LiveKit.
    if (livekitProxy?.upgrade) {
        const getPathname = (rawUrl) => {
            if (!rawUrl) return '';
            const q = rawUrl.indexOf('?');
            return q === -1 ? rawUrl : rawUrl.slice(0, q);
        };

        srv.removeAllListeners('upgrade');

        srv.on('upgrade', (req, socket, head) => {
            const pathname = getPathname(req?.url);

            // Route chat/control WebSocket
            if (pathname === '/ws' || pathname.startsWith('/ws/')) {
                globalWss.handleUpgrade(req, socket, head, (ws) => {
                    globalWss.emit('connection', ws, req);
                });
                return;
            }

            // Route LiveKit signaling proxy
            if (pathname === '/livekit' || pathname.startsWith('/livekit/')) {
                livekitProxy.upgrade(req, socket, head);
                return;
            }

            socket.destroy();
        });
    }
    
    srv.listen(PORT, HOST, () => {
        console.log(`
╔══════════════════════════════════════════════════════════════╗
║           AudioCom Voice Server (LiveKit SFU)                ║
╠══════════════════════════════════════════════════════════════╣
║  Server:   ${protocol.toLowerCase()}://${HOST}:${PORT}                          ║
║  LiveKit:  ${LIVEKIT_URL}                             ║
╠══════════════════════════════════════════════════════════════╣
║  API Endpoints:                                              ║
║    GET  /api/health           - Health check                 ║
║    POST /api/livekit/token    - Get voice token              ║
║    GET  /api/rooms            - List rooms                   ║
║    POST /api/users/register   - Register user                ║
╚══════════════════════════════════════════════════════════════╝
    `);
    });
    
    setupGracefulShutdown(srv);
}
