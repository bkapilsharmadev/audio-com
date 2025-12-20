/**
 * MumbleClient - Handles connection to Mumble server via WebSocket
 * Manages protocol messages and audio streaming
 */
class MumbleClient {
    constructor(options = {}) {
        this.serverUrl = options.serverUrl || this.getDefaultServerUrl();
        this.username = options.username || 'Anonymous';
        
        this.ws = null;
        this.isConnected = false;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.reconnectDelay = 1000;
        
        // User and channel state
        this.currentUser = null;
        this.currentChannel = null;
        this.users = new Map();
        this.channels = new Map();
        
        // Event callbacks
        this.onConnect = null;
        this.onDisconnect = null;
        this.onError = null;
        this.onUserJoin = null;
        this.onUserLeave = null;
        this.onUserSpeaking = null;
        this.onChannelUpdate = null;
        this.onMessage = null;
        
        // Audio handling
        this.audioHandler = null;
        this.peerConnections = new Map(); // For WebRTC
    }

    /**
     * Get default WebSocket server URL
     */
    getDefaultServerUrl() {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        return `${protocol}//${window.location.host}/ws`;
    }

    /**
     * Connect to the Mumble server
     * @param {string} username - Username to connect with
     */
    async connect(username) {
        this.username = username;
        
        return new Promise((resolve, reject) => {
            try {
                console.log('Connecting to:', this.serverUrl);
                this.ws = new WebSocket(this.serverUrl);
                
                this.ws.onopen = () => {
                    console.log('WebSocket connected');
                    this.isConnected = true;
                    this.reconnectAttempts = 0;
                    
                    // Register with the server
                    this.send({
                        type: 'register',
                        userId: this.currentUser?.id
                    });
                    
                    this.onConnect?.();
                    resolve();
                };
                
                this.ws.onclose = (event) => {
                    console.log('WebSocket closed:', event.code, event.reason);
                    this.isConnected = false;
                    this.onDisconnect?.();
                    
                    // Attempt reconnection
                    this.attemptReconnect();
                };
                
                this.ws.onerror = (error) => {
                    console.error('WebSocket error:', error);
                    this.onError?.(error);
                    reject(error);
                };
                
                this.ws.onmessage = (event) => {
                    this.handleMessage(event.data);
                };
                
            } catch (error) {
                console.error('Connection failed:', error);
                reject(error);
            }
        });
    }

    /**
     * Attempt to reconnect after disconnect
     */
    attemptReconnect() {
        if (this.reconnectAttempts >= this.maxReconnectAttempts) {
            console.log('Max reconnection attempts reached');
            return;
        }
        
        this.reconnectAttempts++;
        const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);
        
        console.log(`Attempting reconnect in ${delay}ms (attempt ${this.reconnectAttempts})`);
        
        setTimeout(() => {
            if (!this.isConnected) {
                this.connect(this.username);
            }
        }, delay);
    }

    /**
     * Handle incoming WebSocket messages
     */
    handleMessage(data) {
        try {
            const message = JSON.parse(data);
            console.log('Received message:', message.type, message);
            
            switch (message.type) {
                case 'user-joined':
                    this.handleUserJoin(message);
                    break;
                    
                case 'user-left':
                    this.handleUserLeave(message);
                    break;
                    
                case 'user-speaking':
                    this.handleUserSpeaking(message);
                    break;
                    
                case 'channel-update':
                    this.handleChannelUpdate(message);
                    break;
                    
                case 'chat-message':
                    this.onMessage?.(message);
                    break;
                    
                case 'error':
                    console.error('Server error:', message.error);
                    this.onError?.(new Error(message.error));
                    break;
                    
                default:
                    console.log('Unknown message type:', message.type);
            }
        } catch (error) {
            console.error('Failed to parse message:', error);
        }
    }

    /**
     * Handle user join event
     */
    handleUserJoin(message) {
        const user = {
            id: message.userId,
            name: message.userName,
            isSpeaking: false,
            isMuted: false
        };
        
        this.users.set(message.userId, user);
        this.onUserJoin?.(user);
    }

    /**
     * Handle user leave event
     */
    handleUserLeave(message) {
        const user = this.users.get(message.userId);
        this.users.delete(message.userId);
        this.onUserLeave?.(user || { id: message.userId, name: message.userName });
    }

    /**
     * Handle user speaking state change
     */
    handleUserSpeaking(message) {
        const user = this.users.get(message.userId);
        if (user) {
            user.isSpeaking = message.isSpeaking;
            this.onUserSpeaking?.(user);
        }
    }

    /**
     * Handle channel update
     */
    handleChannelUpdate(message) {
        this.channels.set(message.channelId, {
            id: message.channelId,
            name: message.channelName,
            users: message.users || []
        });
        this.onChannelUpdate?.(message);
    }

    /**
     * Send message to server
     */
    send(message) {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify(message));
        } else {
            console.warn('WebSocket not connected, cannot send message');
        }
    }

    /**
     * Notify server of speaking state
     */
    setSpeaking(isSpeaking) {
        this.send({
            type: 'speaking',
            isSpeaking
        });
    }

    /**
     * Join a channel
     */
    async joinChannel(channelId) {
        this.send({
            type: 'join-room',
            roomId: channelId
        });
        this.currentChannel = channelId;
    }

    /**
     * Leave current channel
     */
    leaveChannel() {
        if (this.currentChannel) {
            this.send({
                type: 'leave-room',
                roomId: this.currentChannel
            });
            this.currentChannel = null;
        }
    }

    /**
     * Send chat message
     */
    sendChatMessage(content) {
        this.send({
            type: 'chat-message',
            content,
            channelId: this.currentChannel
        });
    }

    /**
     * Disconnect from server
     */
    disconnect() {
        this.leaveChannel();
        
        if (this.ws) {
            this.ws.close(1000, 'User disconnected');
            this.ws = null;
        }
        
        this.isConnected = false;
        this.users.clear();
        this.channels.clear();
    }

    /**
     * Set current user data
     */
    setCurrentUser(user) {
        this.currentUser = user;
        if (this.isConnected) {
            this.send({
                type: 'register',
                userId: user.id
            });
        }
    }

    /**
     * Get connection state
     */
    getState() {
        return {
            isConnected: this.isConnected,
            username: this.username,
            currentChannel: this.currentChannel,
            userCount: this.users.size
        };
    }
}

// Export for use
window.MumbleClient = MumbleClient;
