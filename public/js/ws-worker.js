/**
 * WebSocket Worker - Keeps connection alive in background
 * Web Workers are not throttled when the tab is in background
 */

let ws = null;
let wsUrl = null;
let reconnectAttempts = 0;
let maxReconnectAttempts = 10;
let reconnectDelay = 1000;
let heartbeatInterval = null;
let isConnected = false;

// Handle messages from main thread
self.onmessage = function(e) {
    const { type, data } = e.data;
    
    switch (type) {
        case 'connect':
            wsUrl = data.url;
            connect();
            break;
            
        case 'disconnect':
            disconnect();
            break;
            
        case 'send':
            sendMessage(data);
            break;
            
        case 'ping':
            // Respond to ping from main thread (keeps worker alive)
            self.postMessage({ type: 'pong', timestamp: Date.now() });
            break;
    }
};

function connect() {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
        return;
    }
    
    try {
        console.log('[WS Worker] Connecting to:', wsUrl);
        ws = new WebSocket(wsUrl);
        
        ws.onopen = function() {
            console.log('[WS Worker] Connected');
            isConnected = true;
            reconnectAttempts = 0;
            
            // Notify main thread
            self.postMessage({ type: 'connected' });
            
            // Start heartbeat to keep connection alive
            startHeartbeat();
        };
        
        ws.onmessage = function(event) {
            // Forward message to main thread
            try {
                const data = JSON.parse(event.data);
                self.postMessage({ type: 'message', data });
            } catch (e) {
                self.postMessage({ type: 'message', data: event.data });
            }
        };
        
        ws.onclose = function(event) {
            console.log('[WS Worker] Disconnected:', event.code, event.reason);
            isConnected = false;
            stopHeartbeat();
            
            // Notify main thread
            self.postMessage({ type: 'disconnected', code: event.code, reason: event.reason });
            
            // Attempt reconnect if not intentional close
            if (event.code !== 1000 && reconnectAttempts < maxReconnectAttempts) {
                scheduleReconnect();
            }
        };
        
        ws.onerror = function(error) {
            console.error('[WS Worker] Error:', error);
            self.postMessage({ type: 'error', error: 'WebSocket error' });
        };
        
    } catch (error) {
        console.error('[WS Worker] Connection error:', error);
        self.postMessage({ type: 'error', error: error.message });
        scheduleReconnect();
    }
}

function disconnect() {
    console.log('[WS Worker] Disconnecting...');
    stopHeartbeat();
    reconnectAttempts = maxReconnectAttempts; // Prevent reconnect
    
    if (ws) {
        ws.close(1000, 'User disconnected');
        ws = null;
    }
    isConnected = false;
}

function sendMessage(data) {
    if (ws && ws.readyState === WebSocket.OPEN) {
        const message = typeof data === 'string' ? data : JSON.stringify(data);
        ws.send(message);
        return true;
    } else {
        console.warn('[WS Worker] Cannot send - not connected');
        self.postMessage({ type: 'error', error: 'Not connected' });
        return false;
    }
}

function scheduleReconnect() {
    reconnectAttempts++;
    const delay = Math.min(reconnectDelay * Math.pow(2, reconnectAttempts - 1), 30000);
    
    console.log(`[WS Worker] Reconnecting in ${delay}ms (attempt ${reconnectAttempts}/${maxReconnectAttempts})`);
    
    self.postMessage({ 
        type: 'reconnecting', 
        attempt: reconnectAttempts, 
        maxAttempts: maxReconnectAttempts,
        delay 
    });
    
    setTimeout(() => {
        if (reconnectAttempts < maxReconnectAttempts) {
            connect();
        }
    }, delay);
}

function startHeartbeat() {
    stopHeartbeat();
    
    // Send heartbeat every 25 seconds to keep connection alive
    // Most servers have 30-60 second timeouts
    heartbeatInterval = setInterval(() => {
        if (ws && ws.readyState === WebSocket.OPEN) {
            // Send a ping message (server should handle or ignore)
            try {
                ws.send(JSON.stringify({ type: 'heartbeat', timestamp: Date.now() }));
            } catch (e) {
                // Ignore send errors
            }
            
            // Also notify main thread that worker is alive
            self.postMessage({ type: 'heartbeat', timestamp: Date.now() });
        }
    }, 25000);
}

function stopHeartbeat() {
    if (heartbeatInterval) {
        clearInterval(heartbeatInterval);
        heartbeatInterval = null;
    }
}

// Log that worker is ready
console.log('[WS Worker] Initialized and ready');
