/**
 * File-Based Session Store
 * Persists session data to survive server restarts
 * 
 * Stores only intent-level data:
 * - userId, username, roomId, lastSeen
 * 
 * Does NOT store:
 * - socket, networkStatus, speakingState, mediaInfo
 */

const fs = require('fs');
const path = require('path');

// Use local data directory for development, /var/lib/audiocom for production
const DATA_DIR = process.env.SESSION_DIR || path.join(__dirname, 'data');
const FILE_PATH = path.join(DATA_DIR, 'sessions.json');
const TMP_PATH = path.join(DATA_DIR, 'sessions.tmp.json');

class FileSessionStore {
    constructor() {
        this.sessions = new Map();
        this._ensureDataDir();
        this._loadFromDisk();
    }

    _ensureDataDir() {
        if (!fs.existsSync(DATA_DIR)) {
            fs.mkdirSync(DATA_DIR, { recursive: true });
            console.log(`✓ Created session data directory: ${DATA_DIR}`);
        }
    }

    _loadFromDisk() {
        if (!fs.existsSync(FILE_PATH)) {
            console.log('No existing sessions file found, starting fresh');
            return;
        }

        try {
            const raw = fs.readFileSync(FILE_PATH, 'utf8');
            const data = JSON.parse(raw);
            
            for (const s of Object.values(data)) {
                this.sessions.set(s.userId, s);
            }
            
            console.log(`✓ Loaded ${this.sessions.size} sessions from disk`);
        } catch (err) {
            console.error('SessionStore load failed:', err.message);
        }
    }

    _persist() {
        try {
            const obj = Object.fromEntries(this.sessions);
            fs.writeFileSync(TMP_PATH, JSON.stringify(obj, null, 2));
            fs.renameSync(TMP_PATH, FILE_PATH); // atomic replace
        } catch (err) {
            console.error('SessionStore persist failed:', err.message);
        }
    }

    /**
     * Save or update a session
     * @param {Object} session - { userId, username, roomId, lastSeen }
     */
    save(session) {
        // Ensure lastSeen is set
        if (!session.lastSeen) {
            session.lastSeen = Date.now();
        }
        
        this.sessions.set(session.userId, {
            userId: session.userId,
            username: session.username,
            roomId: session.roomId,
            lastSeen: session.lastSeen
        });
        
        this._persist();
    }

    /**
     * Remove a session by userId
     */
    remove(userId) {
        if (this.sessions.has(userId)) {
            this.sessions.delete(userId);
            this._persist();
            return true;
        }
        return false;
    }

    /**
     * Get a session by userId
     */
    get(userId) {
        return this.sessions.get(userId) || null;
    }

    /**
     * Get all sessions in a room
     */
    getByRoom(roomId) {
        return [...this.sessions.values()].filter(s => s.roomId === roomId);
    }

    /**
     * Get all sessions
     */
    getAll() {
        return [...this.sessions.values()];
    }

    /**
     * Check if a username is taken (by a different userId)
     */
    isUsernameTaken(username, excludeUserId = null) {
        const lowerName = username.toLowerCase();
        for (const s of this.sessions.values()) {
            if (s.username.toLowerCase() === lowerName && s.userId !== excludeUserId) {
                return s;
            }
        }
        return null;
    }

    /**
     * Update lastSeen timestamp for a user
     */
    touch(userId) {
        const session = this.sessions.get(userId);
        if (session) {
            session.lastSeen = Date.now();
            this._persist();
            return true;
        }
        return false;
    }

    /**
     * Clean up expired sessions
     * @param {number} expiryMs - Expiry time in milliseconds
     * @param {Set<string>} activeUserIds - Set of userIds with active WebSocket connections (skip these)
     * @returns {string[]} - Array of removed userIds
     */
    cleanup(expiryMs, activeUserIds = new Set()) {
        const now = Date.now();
        const removed = [];

        for (const [userId, s] of this.sessions) {
            // Skip users with active WebSocket connections - they're still being tracked
            if (activeUserIds.has(userId)) {
                continue;
            }
            
            if (now - s.lastSeen > expiryMs) {
                this.sessions.delete(userId);
                removed.push({ userId, username: s.username });
            }
        }

        if (removed.length > 0) {
            this._persist();
            console.log(`✓ Cleaned up ${removed.length} stale sessions`);
        }

        return removed;
    }

    /**
     * Get session count
     */
    get size() {
        return this.sessions.size;
    }
}

// Singleton instance
const sessionStore = new FileSessionStore();

module.exports = { sessionStore };
