/**
 * AudioCom - Main Application
 * Orchestrates UI, audio handling, and server communication
 */

// Application state
const app = {
    user: null,
    token: null,
    currentRoom: null,
    rooms: [],
    users: [],
    
    audioHandler: null,
    mumbleClient: null,
    livekitVoice: null,  // LiveKit SFU for voice
    
    // DOM elements cache
    elements: {}
};

/**
 * Initialize the application
 */
async function initializeApp() {
    console.log('Initializing AudioCom...');
    
    // Cache DOM elements
    cacheElements();
    
    // Setup event listeners
    setupEventListeners();
    
    // Check for invite code in URL
    checkInviteCode();
    
    console.log('AudioCom initialized');
}

/**
 * Cache frequently used DOM elements
 */
function cacheElements() {
    app.elements = {
        // Modals
        loginModal: document.getElementById('login-modal'),
        createRoomModal: document.getElementById('create-room-modal'),
        settingsModal: document.getElementById('settings-modal'),
        mainApp: document.getElementById('main-app'),
        
        // Login
        loginForm: document.getElementById('login-form'),
        usernameInput: document.getElementById('username-input'),
        loginError: document.getElementById('login-error'),
        
        // User info
        currentUsername: document.getElementById('current-username'),
        currentRoomName: document.getElementById('current-room-name'),
        avatarInitial: document.getElementById('avatar-initial'),
        
        // Rooms and users
        roomList: document.getElementById('room-list'),
        userList: document.getElementById('user-list'),
        userCount: document.getElementById('user-count'),
        
        // Voice controls
        activeRoomName: document.getElementById('active-room-name'),
        activeRoomUsers: document.getElementById('active-room-users'),
        muteBtn: document.getElementById('mute-btn'),
        enableAudioBtn: document.getElementById('enable-audio-btn'),
        deafenBtn: document.getElementById('deafen-btn'),
        disconnectBtn: document.getElementById('disconnect-btn'),
        connectionIndicator: document.getElementById('connection-indicator'),
        connectionText: document.getElementById('connection-text'),
        
        // Voice grid
        voiceGrid: document.getElementById('voice-grid'),
        
        // Chat
        chatForm: document.getElementById('chat-form'),
        chatInput: document.getElementById('chat-input'),
        chatMessages: document.getElementById('chat-messages'),
        chatSection: document.querySelector('.chat-section'),
        toggleChatBtn: document.getElementById('toggle-chat-btn'),
        
        // Create room
        createRoomBtn: document.getElementById('create-room-btn'),
        createRoomForm: document.getElementById('create-room-form'),
        roomNameInput: document.getElementById('room-name-input'),
        roomDescriptionInput: document.getElementById('room-description-input'),
        roomMaxUsers: document.getElementById('room-max-users'),
        
        // Settings
        settingsBtn: document.getElementById('settings-btn'),
        inputDevice: document.getElementById('input-device'),
        outputDevice: document.getElementById('output-device'),
        inputVolume: document.getElementById('input-volume'),
        outputVolume: document.getElementById('output-volume'),
        inputVolumeValue: document.getElementById('input-volume-value'),
        outputVolumeValue: document.getElementById('output-volume-value'),
        inputMeter: document.getElementById('input-meter'),
        voiceActivation: document.getElementById('voice-activation'),
        vadThreshold: document.getElementById('vad-threshold'),
        pushToTalk: document.getElementById('push-to-talk'),
        noiseSuppression: document.getElementById('noise-suppression'),
        echoCancellation: document.getElementById('echo-cancellation'),
        autoGain: document.getElementById('auto-gain'),
        
        // Mobile elements
        menuToggle: document.getElementById('menu-toggle'),
        sidebar: document.querySelector('.sidebar'),
        sidebarOverlay: document.getElementById('sidebar-overlay'),
        mobileRoomName: document.getElementById('mobile-room-name'),
        mobileSettingsBtn: document.getElementById('mobile-settings-btn'),
        headphoneWarning: document.getElementById('headphone-warning'),
        dismissWarning: document.getElementById('dismiss-warning')
    };
}

/**
 * Setup event listeners
 */
function setupEventListeners() {
    // Login form
    app.elements.loginForm.addEventListener('submit', handleLogin);
    
    // Voice controls
    app.elements.muteBtn.addEventListener('click', toggleMute);
    const enableAudioHandler = () => {
        console.log('🎵 Enabling audio playback on user interaction...');
        let audioCount = 0;
        document.querySelectorAll('audio').forEach((audio) => {
            audio.muted = false;
            const playPromise = audio.play();
            if (playPromise !== undefined) {
                playPromise
                    .then(() => {
                        audioCount++;
                        console.log(`✓ Audio playing (${audioCount})`);
                    })
                    .catch(e => console.warn(`⚠ ${e.message}`));
            }
        });
        // Hide button after first use
        app.elements.enableAudioBtn.style.display = 'none';
        showNotification('🔊 Speaker enabled', 'success');
    };
    app.elements.enableAudioBtn.addEventListener('click', enableAudioHandler);
    app.elements.enableAudioBtn.addEventListener('touchstart', enableAudioHandler);
    app.elements.deafenBtn.addEventListener('click', toggleDeafen);
    app.elements.disconnectBtn.addEventListener('click', handleDisconnect);
    
    // Chat
    app.elements.chatForm.addEventListener('submit', handleChatSubmit);
    app.elements.toggleChatBtn?.addEventListener('click', toggleChat);
    app.elements.chatSection?.querySelector('.chat-header')?.addEventListener('click', toggleChat);
    
    // Create room
    app.elements.createRoomBtn.addEventListener('click', () => openModal('createRoomModal'));
    app.elements.createRoomForm.addEventListener('submit', handleCreateRoom);
    
    // Settings
    app.elements.settingsBtn.addEventListener('click', () => openModal('settingsModal'));
    app.elements.mobileSettingsBtn?.addEventListener('click', () => openModal('settingsModal'));
    app.elements.inputVolume.addEventListener('input', handleInputVolumeChange);
    app.elements.outputVolume.addEventListener('input', handleOutputVolumeChange);
    app.elements.vadThreshold.addEventListener('input', handleVADThresholdChange);
    app.elements.inputDevice.addEventListener('change', handleInputDeviceChange);
    app.elements.outputDevice?.addEventListener('change', handleOutputDeviceChange);
    app.elements.noiseSuppression?.addEventListener('change', handleNoiseSuppressionToggle);
    
    // Audio quality settings
    app.elements.pushToTalk?.addEventListener('change', handlePushToTalkToggle);
    app.elements.voiceActivation?.addEventListener('change', handleVADToggle);
    
    // Mobile menu
    app.elements.menuToggle?.addEventListener('click', toggleSidebar);
    app.elements.sidebarOverlay?.addEventListener('click', closeSidebar);
    app.elements.dismissWarning?.addEventListener('click', dismissHeadphoneWarning);
    
    // Modal close buttons
    document.querySelectorAll('.modal-close').forEach(btn => {
        btn.addEventListener('click', closeAllModals);
    });
    
    // Close modal on backdrop click
    document.querySelectorAll('.modal').forEach(modal => {
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                closeAllModals();
            }
        });
    });
    
    // Keyboard shortcuts
    document.addEventListener('keydown', handleKeyDown);
    
    // Enable audio autoplay on first user interaction (browser autoplay policy)
    // This is required for mobile browsers
    const enableAudioPlayback = () => {
        console.log('🎵 Enabling audio playback...');
        document.querySelectorAll('audio').forEach((audio, index) => {
            console.log(`  Playing audio element ${index}...`);
            audio.muted = false;
            const playPromise = audio.play();
            if (playPromise !== undefined) {
                playPromise
                    .then(() => console.log(`  ✓ Audio ${index} playing`))
                    .catch(e => console.log(`  ℹ Audio ${index}: ${e.message}`));
            }
        });
    };
    
    document.addEventListener('click', enableAudioPlayback, { once: true });
    document.addEventListener('touchstart', enableAudioPlayback, { once: true });
}

/**
 * Handle login form submission
 */
async function handleLogin(e) {
    e.preventDefault();
    
    const username = app.elements.usernameInput.value.trim();
    
    if (!username) {
        showLoginError('Please enter a username');
        return;
    }
    
    try {
        showLoginError(''); // Clear any previous error
        
        // Register user with API
        const response = await fetch('/api/users/register', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name: username })
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.error || 'Registration failed');
        }
        
        // Store user data
        app.user = {
            id: data.id,
            name: data.name,
            roomId: data.roomId
        };
        app.token = data.token;
        
        // Initialize audio
        await initializeAudio();
        
        // Connect to WebSocket
        await connectToServer();
        
        // Load rooms and users
        await loadRooms();
        await loadUsers();
        
        // Update UI
        updateUserInfo();
        
        // Switch to main app
        app.elements.loginModal.classList.remove('active');
        app.elements.mainApp.classList.remove('hidden');
        
        // Join default room (lobby)
        if (app.currentRoom) {
            joinRoom(app.currentRoom);
        } else {
            joinRoom('lobby');
        }
        
    } catch (error) {
        console.error('Login failed:', error);
        showLoginError(error.message);
    }
}

/**
 * Initialize audio handler
 */
async function initializeAudio() {
    app.audioHandler = new AudioHandler();
    await app.audioHandler.initialize();
    await app.audioHandler.startCapture();
    
    // Setup speaking callback
    app.audioHandler.onSpeakingChange = (isSpeaking) => {
        if (app.mumbleClient) {
            app.mumbleClient.setSpeaking(isSpeaking);
        }
        updateSpeakingState(isSpeaking);
    };
    
    // Setup volume level callback for meter
    app.audioHandler.onVolumeLevel = (level) => {
        if (app.elements.inputMeter) {
            app.elements.inputMeter.style.width = `${level * 100}%`;
        }
    };
    
    // Populate device lists
    populateDeviceLists();
}

/**
 * Connect to WebSocket server
 */
async function connectToServer() {
    app.mumbleClient = new MumbleClient({
        username: app.user.name
    });
    
    app.mumbleClient.setCurrentUser(app.user);
    
    // Setup callbacks
    app.mumbleClient.onConnect = () => {
        updateConnectionStatus(true);
    };
    
    app.mumbleClient.onDisconnect = () => {
        updateConnectionStatus(false);
    };
    
    app.mumbleClient.onUserJoin = (user) => {
        addUserToList(user);
        addUserToVoiceGrid(user);
        showNotification(`${user.name} joined`);
    };
    
    app.mumbleClient.onUserLeave = (user) => {
        removeUserFromList(user.id);
        removeUserFromVoiceGrid(user.id);
        if (user.name) {
            showNotification(`${user.name} left`);
        }
    };
    
    app.mumbleClient.onUserSpeaking = (user) => {
        updateUserSpeakingState(user.id, user.isSpeaking);
    };
    
    app.mumbleClient.onMessage = (message) => {
        addChatMessage(message);
    };
    
    await app.mumbleClient.connect(app.user.name);
}

/**
 * Load rooms from API
 */
async function loadRooms() {
    try {
        const response = await fetch('/api/rooms');
        app.rooms = await response.json();
        renderRoomList();
    } catch (error) {
        console.error('Failed to load rooms:', error);
    }
}

/**
 * Load users from API
 */
async function loadUsers() {
    try {
        const response = await fetch('/api/users');
        app.users = await response.json();
        renderUserList();
        updateVoiceGrid();
    } catch (error) {
        console.error('Failed to load users:', error);
    }
}

/**
 * Render room list
 */
function renderRoomList() {
    const roomList = app.elements.roomList;
    roomList.innerHTML = '';
    
    app.rooms.forEach(room => {
        const li = document.createElement('li');
        li.className = `room-item ${room.id === app.user?.roomId ? 'active' : ''}`;
        li.dataset.roomId = room.id;
        
        li.innerHTML = `
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
            </svg>
            <div class="room-item-info">
                <span class="room-item-name">${escapeHtml(room.name)}</span>
                <span class="room-item-users">${room.userCount} users</span>
            </div>
        `;
        
        li.addEventListener('click', () => joinRoom(room.id));
        roomList.appendChild(li);
    });
}

/**
 * Render user list
 */
function renderUserList() {
    const userList = app.elements.userList;
    userList.innerHTML = '';
    
    // Filter users in current room
    const roomUsers = app.users.filter(u => u.roomId === app.user?.roomId);
    
    app.elements.userCount.textContent = roomUsers.length;
    
    roomUsers.forEach(user => {
        addUserToList(user);
    });
}

/**
 * Add user to list
 */
function addUserToList(user) {
    // Don't add if already exists
    if (document.querySelector(`[data-user-id="${user.id}"]`)) return;
    
    const li = document.createElement('li');
    li.className = 'user-item';
    li.dataset.userId = user.id;
    
    const initial = user.name.charAt(0).toUpperCase();
    const isMe = user.id === app.user?.id;
    
    li.innerHTML = `
        <div class="user-avatar ${user.isSpeaking ? 'speaking' : ''}">
            <span>${initial}</span>
            <div class="status-indicator ${user.isMuted ? 'muted' : 'online'}"></div>
        </div>
        <span class="user-item-name">${escapeHtml(user.name)}${isMe ? ' (you)' : ''}</span>
        <div class="user-item-status">
            ${user.isMuted ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12"/></svg>' : ''}
            ${user.isDeafened ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="1" y1="1" x2="23" y2="23"/><path d="M3 18v-6a9 9 0 0 1 14.77-6.94"/></svg>' : ''}
        </div>
    `;
    
    // Click to start private call (if not self)
    if (!isMe) {
        li.addEventListener('click', () => startPrivateCall(user));
    }
    
    app.elements.userList.appendChild(li);
    updateUserCount();
}

/**
 * Remove user from list
 */
function removeUserFromList(userId) {
    const userElement = document.querySelector(`[data-user-id="${userId}"]`);
    if (userElement) {
        userElement.remove();
    }
    updateUserCount();
}

/**
 * Update user count badge
 */
function updateUserCount() {
    const count = app.elements.userList.children.length;
    app.elements.userCount.textContent = count;
    app.elements.activeRoomUsers.textContent = `${count} user${count !== 1 ? 's' : ''}`;
}

/**
 * Join a room
 */
async function joinRoom(roomId) {
    try {
        const response = await fetch(`/api/users/${app.user.id}/join/${roomId}`, {
            method: 'POST'
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.error);
        }
        
        // Update state
        app.user.roomId = roomId;
        
        // Update UI
        updateActiveRoom(data.roomName);
        
        // Close sidebar on mobile after joining room
        closeSidebar();
        
        // Reload users for new room
        await loadUsers();
        
        // Update room list selection
        document.querySelectorAll('.room-item').forEach(item => {
            item.classList.toggle('active', item.dataset.roomId === roomId);
        });
        
        // Notify server
        app.mumbleClient?.joinChannel(roomId);
        
        // Update voice grid
        updateVoiceGrid();
        
        // Initialize LiveKit voice for this room
        initializeLiveKitVoice(roomId);
        
    } catch (error) {
        console.error('Failed to join room:', error);
        showNotification(error.message, 'error');
    }
}

/**
 * Initialize LiveKit voice chat for room (SFU - efficient for mobile)
 */
async function initializeLiveKitVoice(roomId) {
    // Clean up existing connection
    if (app.livekitVoice) {
        app.livekitVoice.disconnect();
    }
    
    // Check if LiveKitVoice is available
    if (typeof LiveKitVoice === 'undefined') {
        console.warn('LiveKitVoice not available');
        return;
    }
    
    // Check if LiveKit SDK is loaded
    if (typeof LivekitClient === 'undefined') {
        console.warn('LiveKit SDK not loaded - voice unavailable');
        showNotification('Voice server not available', 'warning');
        return;
    }
    
    try {
        app.livekitVoice = new LiveKitVoice();
        
        // Handle participant events
        app.livekitVoice.onParticipantJoined = (participant) => {
            console.log('Voice: participant joined:', participant.name);
            showNotification(`${participant.name} joined voice`);
        };
        
        app.livekitVoice.onParticipantLeft = (participant) => {
            console.log('Voice: participant left:', participant.name);
        };
        
        app.livekitVoice.onSpeakingChanged = (speakingIds) => {
            // Update speaking indicators in UI
            app.users.forEach(user => {
                const isSpeaking = speakingIds.includes(user.id);
                updateUserSpeakingState(user.id, isSpeaking);
            });
        };
        
        app.livekitVoice.onConnectionStateChanged = (connected) => {
            updateConnectionStatus(connected);
            if (connected) {
                showNotification('Voice connected');
            }
        };
        
        app.livekitVoice.onError = (error) => {
            console.error('LiveKit error:', error);
            showNotification('Voice error: ' + error.message, 'error');
        };
        
        // Handle latency updates
        app.livekitVoice.onLatencyUpdate = (stats) => {
            updateLatencyDisplay(stats);
        };
        
        // Handle VAD state changes (visual feedback for when mic is auto-muted)
        app.livekitVoice.onVADStateChanged = (isSpeaking) => {
            const muteBtn = app.elements.muteBtn;
            if (muteBtn && app.livekitVoice?.vadEnabled) {
                if (isSpeaking) {
                    muteBtn.classList.add('speaking');
                    muteBtn.title = 'Speaking (VAD active)';
                } else {
                    muteBtn.classList.remove('speaking');
                    muteBtn.title = 'Silent (VAD active)';
                }
            }
        };
        
        // Connect to LiveKit room
        const connected = await app.livekitVoice.connect(roomId, app.user.id, app.user.name);
        
        if (connected) {
            console.log('LiveKit voice initialized for room:', roomId);
            // Check and show headphone warning
            checkHeadphoneWarning();
        } else {
            console.warn('Could not connect to voice server');
        }
        
    } catch (error) {
        console.error('Failed to initialize LiveKit voice:', error);
        showNotification('Voice unavailable', 'warning');
    }
}

/**
 * Update active room display
 */
function updateActiveRoom(roomName) {
    app.elements.activeRoomName.textContent = roomName;
    app.elements.currentRoomName.textContent = roomName;
    updateMobileRoomName(roomName);
}

/**
 * Update voice grid with current room users
 */
function updateVoiceGrid() {
    const grid = app.elements.voiceGrid;
    
    // Get users in current room
    const roomUsers = app.users.filter(u => u.roomId === app.user?.roomId);
    
    if (roomUsers.length === 0) {
        grid.innerHTML = `
            <div class="voice-placeholder">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                    <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
                    <circle cx="9" cy="7" r="4"/>
                    <path d="M23 21v-2a4 4 0 0 0-3-3.87"/>
                    <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
                </svg>
                <p>No other users in this channel</p>
            </div>
        `;
        return;
    }
    
    grid.innerHTML = '';
    roomUsers.forEach(user => {
        addUserToVoiceGrid(user);
    });
}

/**
 * Add user to voice grid
 */
function addUserToVoiceGrid(user) {
    // Remove placeholder if exists
    const placeholder = app.elements.voiceGrid.querySelector('.voice-placeholder');
    if (placeholder) placeholder.remove();
    
    // Don't add if already exists
    if (document.querySelector(`.voice-card[data-user-id="${user.id}"]`)) return;
    
    const initial = user.name.charAt(0).toUpperCase();
    const isMe = user.id === app.user?.id;
    
    const card = document.createElement('div');
    card.className = `voice-card ${user.isSpeaking ? 'speaking' : ''}`;
    card.dataset.userId = user.id;
    
    card.innerHTML = `
        <div class="user-avatar ${user.isSpeaking ? 'speaking' : ''}">
            <span>${initial}</span>
        </div>
        <div class="user-name">${escapeHtml(user.name)}${isMe ? ' (you)' : ''}</div>
        <div class="voice-indicator">
            <div class="bar"></div>
            <div class="bar"></div>
            <div class="bar"></div>
            <div class="bar"></div>
            <div class="bar"></div>
        </div>
    `;
    
    app.elements.voiceGrid.appendChild(card);
}

/**
 * Remove user from voice grid
 */
function removeUserFromVoiceGrid(userId) {
    const card = document.querySelector(`.voice-card[data-user-id="${userId}"]`);
    if (card) {
        card.remove();
    }
    
    // Show placeholder if grid is empty
    if (app.elements.voiceGrid.children.length === 0) {
        updateVoiceGrid();
    }
}

/**
 * Update user speaking state in UI
 */
function updateUserSpeakingState(userId, isSpeaking) {
    // Update in user list
    const userListItem = document.querySelector(`.user-item[data-user-id="${userId}"]`);
    if (userListItem) {
        const avatar = userListItem.querySelector('.user-avatar');
        avatar?.classList.toggle('speaking', isSpeaking);
    }
    
    // Update in voice grid
    const voiceCard = document.querySelector(`.voice-card[data-user-id="${userId}"]`);
    if (voiceCard) {
        voiceCard.classList.toggle('speaking', isSpeaking);
        const avatar = voiceCard.querySelector('.user-avatar');
        avatar?.classList.toggle('speaking', isSpeaking);
    }
}

/**
 * Update own speaking state
 */
function updateSpeakingState(isSpeaking) {
    if (app.user) {
        updateUserSpeakingState(app.user.id, isSpeaking);
    }
}

/**
 * Toggle mute
 */
async function toggleMute() {
    let isMuted = false;
    
    // Control LiveKit if available
    if (app.livekitVoice) {
        // When manually toggling mute, disable VAD/PTT mode to give full control
        if (app.livekitVoice.vadEnabled || app.livekitVoice.isPushToTalk) {
            console.log('[Audio] Manual mute toggle - disabling VAD/PTT');
            app.livekitVoice.setVADEnabled(false);
            app.livekitVoice.setPushToTalk(false);
            if (app.elements.voiceActivation) app.elements.voiceActivation.checked = false;
            if (app.elements.pushToTalk) app.elements.pushToTalk.checked = false;
        }
        isMuted = app.livekitVoice.toggleMute();
    } else if (app.audioHandler) {
        isMuted = app.audioHandler.toggleMute();
    }
    
    app.elements.muteBtn.classList.toggle('active', isMuted);
    app.elements.muteBtn.querySelector('.icon-mic').classList.toggle('hidden', isMuted);
    app.elements.muteBtn.querySelector('.icon-mic-off').classList.toggle('hidden', !isMuted);
    
    // Update server
    await fetch(`/api/users/${app.user.id}/state`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isMuted })
    });
}

/**
 * Toggle deafen
 */
async function toggleDeafen() {
    let isDeafened = false;
    
    // Control LiveKit if available
    if (app.livekitVoice) {
        isDeafened = app.livekitVoice.toggleDeafen();
    } else if (app.audioHandler) {
        isDeafened = app.audioHandler.toggleDeafen();
    }
    
    app.elements.deafenBtn.classList.toggle('active', isDeafened);
    app.elements.deafenBtn.querySelector('.icon-headphones').classList.toggle('hidden', isDeafened);
    app.elements.deafenBtn.querySelector('.icon-headphones-off').classList.toggle('hidden', !isDeafened);
    
    // If deafened, also mute mic and show muted state
    if (isDeafened) {
        if (app.livekitVoice && !app.livekitVoice.isMuted) {
            app.livekitVoice.setMuted(true);
        }
        app.elements.muteBtn.classList.add('active');
        app.elements.muteBtn.querySelector('.icon-mic').classList.add('hidden');
        app.elements.muteBtn.querySelector('.icon-mic-off').classList.remove('hidden');
    }
    
    // Update server
    await fetch(`/api/users/${app.user.id}/state`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isDeafened, isMuted: isDeafened })
    });
}

/**
 * Handle disconnect
 */
async function handleDisconnect() {
    try {
        // Stop audio
        app.audioHandler?.destroy();
        
        // Disconnect LiveKit voice
        if (app.livekitVoice) {
            app.livekitVoice.disconnect();
            app.livekitVoice = null;
        }
        
        // Disconnect WebSocket
        app.mumbleClient?.disconnect();
        
        // Leave on server
        await fetch(`/api/users/${app.user.id}/leave`, {
            method: 'POST'
        });
        
        // Reset state
        app.user = null;
        app.token = null;
        app.currentRoom = null;
        
        // Reset UI
        app.elements.muteBtn.classList.remove('active');
        app.elements.muteBtn.querySelector('.icon-mic').classList.remove('hidden');
        app.elements.muteBtn.querySelector('.icon-mic-off').classList.add('hidden');
        app.elements.deafenBtn.classList.remove('active');
        app.elements.deafenBtn.querySelector('.icon-headphones').classList.remove('hidden');
        app.elements.deafenBtn.querySelector('.icon-headphones-off').classList.add('hidden');
        app.elements.connectionText.textContent = 'Disconnected';
        
        // Show login modal
        app.elements.mainApp.classList.add('hidden');
        app.elements.loginModal.classList.add('active');
        app.elements.usernameInput.value = '';
        
    } catch (error) {
        console.error('Disconnect error:', error);
    }
}

/**
 * Handle chat submit
 */
function handleChatSubmit(e) {
    e.preventDefault();
    
    const content = app.elements.chatInput.value.trim();
    if (!content) return;
    
    // Add message to UI
    addChatMessage({
        sender: app.user.name,
        content,
        timestamp: new Date().toISOString()
    });
    
    // Send to server
    app.mumbleClient?.sendChatMessage(content);
    
    // Clear input
    app.elements.chatInput.value = '';
}

/**
 * Add chat message to UI
 */
function addChatMessage(message) {
    const messagesContainer = app.elements.chatMessages;
    
    // Remove welcome message if exists
    const welcome = messagesContainer.querySelector('.welcome-message');
    if (welcome) welcome.remove();
    
    const time = new Date(message.timestamp || Date.now()).toLocaleTimeString([], {
        hour: '2-digit',
        minute: '2-digit'
    });
    
    const div = document.createElement('div');
    div.className = 'chat-message';
    div.innerHTML = `
        <span class="sender">${escapeHtml(message.sender || 'Unknown')}</span>
        <span class="time">${time}</span>
        <div class="content">${escapeHtml(message.content)}</div>
    `;
    
    messagesContainer.appendChild(div);
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
}

/**
 * Handle create room
 */
async function handleCreateRoom(e) {
    e.preventDefault();
    
    const name = app.elements.roomNameInput.value.trim();
    const description = app.elements.roomDescriptionInput.value.trim();
    const maxUsers = parseInt(app.elements.roomMaxUsers.value) || 25;
    
    if (!name) return;
    
    try {
        const response = await fetch('/api/rooms', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, description, maxUsers })
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.error);
        }
        
        // Close modal
        closeAllModals();
        
        // Reload rooms
        await loadRooms();
        
        // Join new room
        joinRoom(data.id);
        
        // Reset form
        app.elements.createRoomForm.reset();
        
    } catch (error) {
        console.error('Failed to create room:', error);
        showNotification(error.message, 'error');
    }
}

/**
 * Start private call with user
 */
async function startPrivateCall(user) {
    try {
        const response = await fetch('/api/rooms/private', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                userId1: app.user.id,
                userId2: user.id
            })
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.error);
        }
        
        // Join private room
        await joinRoom(data.id);
        
        showNotification(`Started private call with ${user.name}`);
        
    } catch (error) {
        console.error('Failed to start private call:', error);
        showNotification(error.message, 'error');
    }
}

/**
 * Update user info display
 */
function updateUserInfo() {
    if (!app.user) return;
    
    app.elements.currentUsername.textContent = app.user.name;
    app.elements.avatarInitial.textContent = app.user.name.charAt(0).toUpperCase();
}

/**
 * Update connection status
 */
function updateConnectionStatus(isConnected) {
    app.elements.connectionIndicator.classList.toggle('connected', isConnected);
    app.elements.connectionIndicator.classList.toggle('disconnected', !isConnected);
    app.elements.connectionText.textContent = isConnected ? 'Connected' : 'Disconnected';
}

/**
 * Update latency display
 */
function updateLatencyDisplay(stats) {
    const connectionText = app.elements.connectionText;
    
    if (!stats || !app.livekitVoice?.isConnected) {
        connectionText.textContent = 'Connected';
        return;
    }
    
    // Determine quality based on RTT
    let quality = 'excellent';
    let color = '#4ade80'; // green
    
    if (stats.roundTripTime > 150) {
        quality = 'poor';
        color = '#ef4444'; // red
    } else if (stats.roundTripTime > 100) {
        quality = 'fair';
        color = '#f59e0b'; // orange
    } else if (stats.roundTripTime > 50) {
        quality = 'good';
        color = '#84cc16'; // lime
    }
    
    // Update connection indicator color
    app.elements.connectionIndicator.style.setProperty('--pulse-color', color);
    
    // Display latency info
    if (stats.roundTripTime > 0) {
        connectionText.textContent = `${stats.roundTripTime}ms`;
        connectionText.title = `RTT: ${stats.roundTripTime}ms | Jitter: ${stats.jitter}ms | Quality: ${quality}`;
    } else {
        connectionText.textContent = 'Connected';
        connectionText.title = 'Measuring latency...';
    }
}

/**
 * Populate device selection lists
 */
function populateDeviceLists() {
    if (!app.audioHandler) return;
    
    const { inputs, outputs } = app.audioHandler.audioDevices;
    
    // Input devices
    app.elements.inputDevice.innerHTML = '<option value="">Default Microphone</option>';
    inputs.forEach(device => {
        const option = document.createElement('option');
        option.value = device.deviceId;
        option.textContent = device.label || `Microphone ${device.deviceId.slice(0, 8)}`;
        app.elements.inputDevice.appendChild(option);
    });
    
    // Output devices
    app.elements.outputDevice.innerHTML = '<option value="">Default Speakers</option>';
    outputs.forEach(device => {
        const option = document.createElement('option');
        option.value = device.deviceId;
        option.textContent = device.label || `Speaker ${device.deviceId.slice(0, 8)}`;
        app.elements.outputDevice.appendChild(option);
    });
}

/**
 * Handle input volume change
 */
function handleInputVolumeChange() {
    const value = parseInt(app.elements.inputVolume.value);
    app.elements.inputVolumeValue.textContent = `${value}%`;
    
    // LiveKit doesn't support direct input gain, but we track it
    if (app.livekitVoice) {
        app.livekitVoice.setInputVolume(value / 100);
    } else if (app.audioHandler) {
        app.audioHandler.setInputVolume(value / 100);
    }
}

/**
 * Handle output volume change
 */
function handleOutputVolumeChange() {
    const value = parseInt(app.elements.outputVolume.value);
    app.elements.outputVolumeValue.textContent = `${value}%`;
    
    if (app.livekitVoice) {
        app.livekitVoice.setOutputVolume(value / 100);
    } else if (app.audioHandler) {
        app.audioHandler.setOutputVolume(value / 100);
    }
}

/**
 * Handle VAD threshold change
 */
function handleVADThresholdChange() {
    const value = parseInt(app.elements.vadThreshold.value);
    // Map slider 0-100 to threshold 0.001-0.05 (lower = more sensitive)
    const threshold = 0.001 + (value / 100) * 0.049;
    app.livekitVoice?.setVADThreshold(threshold);
    console.log('[Audio] VAD threshold:', threshold.toFixed(4));
}

/**
 * Handle input device change
 */
async function handleInputDeviceChange() {
    const deviceId = app.elements.inputDevice.value;
    
    if (app.livekitVoice) {
        await app.livekitVoice.changeInputDevice(deviceId || null);
    } else if (app.audioHandler) {
        await app.audioHandler.changeInputDevice(deviceId || null);
    }
}

/**
 * Handle output device change
 */
async function handleOutputDeviceChange() {
    const deviceId = app.elements.outputDevice?.value;
    
    if (app.livekitVoice) {
        await app.livekitVoice.changeOutputDevice(deviceId || null);
    } else if (app.audioHandler) {
        await app.audioHandler.changeOutputDevice(deviceId || null);
    }
}

/**
 * Handle noise suppression toggle
 */
async function handleNoiseSuppressionToggle() {
    const enabled = app.elements.noiseSuppression?.checked ?? true;
    
    if (app.livekitVoice) {
        await app.livekitVoice.setNoiseSuppression(enabled);
        console.log('[Audio] Noise suppression:', enabled ? 'enabled' : 'disabled');
    }
}

/**
 * Handle Push-to-Talk toggle
 */
function handlePushToTalkToggle() {
    const enabled = app.elements.pushToTalk?.checked || false;
    
    // Disable VAD first if PTT is being enabled
    if (enabled && app.elements.voiceActivation) {
        app.elements.voiceActivation.checked = false;
        app.livekitVoice?.setVADEnabled(false);
    }
    
    if (app.livekitVoice) {
        app.livekitVoice.setPushToTalk(enabled);
        console.log('[Audio] Push-to-talk:', enabled ? 'enabled' : 'disabled');
        
        // Update mute button UI
        updateMuteButtonUI();
    }
}

/**
 * Handle VAD toggle
 */
function handleVADToggle() {
    const enabled = app.elements.voiceActivation?.checked || false;
    
    // Disable PTT first if VAD is being enabled
    if (enabled && app.elements.pushToTalk) {
        app.elements.pushToTalk.checked = false;
        app.livekitVoice?.setPushToTalk(false);
    }
    
    if (app.livekitVoice) {
        app.livekitVoice.setVADEnabled(enabled);
        console.log('[Audio] VAD:', enabled ? 'enabled' : 'disabled');
        
        // Update mute button UI
        updateMuteButtonUI();
    }
}

/**
 * Update the mute button UI to reflect current state
 */
function updateMuteButtonUI() {
    if (!app.livekitVoice || !app.elements.muteBtn) return;
    
    const isMuted = app.livekitVoice.isMuted;
    const iconMic = app.elements.muteBtn.querySelector('.icon-mic');
    const iconMicOff = app.elements.muteBtn.querySelector('.icon-mic-off');
    
    if (isMuted) {
        iconMic?.classList.add('hidden');
        iconMicOff?.classList.remove('hidden');
        app.elements.muteBtn.classList.add('active');
    } else {
        iconMic?.classList.remove('hidden');
        iconMicOff?.classList.add('hidden');
        app.elements.muteBtn.classList.remove('active');
    }
}

/**
 * Toggle sidebar on mobile
 */
function toggleSidebar() {
    app.elements.sidebar?.classList.toggle('open');
    app.elements.sidebarOverlay?.classList.toggle('active');
}

/**
 * Close sidebar on mobile
 */
function closeSidebar() {
    app.elements.sidebar?.classList.remove('open');
    app.elements.sidebarOverlay?.classList.remove('active');
}

/**
 * Toggle chat section on mobile
 */
function toggleChat() {
    app.elements.chatSection?.classList.toggle('expanded');
}

/**
 * Dismiss headphone warning
 */
function dismissHeadphoneWarning() {
    app.elements.headphoneWarning?.classList.add('hidden');
    localStorage.setItem('headphoneWarningDismissed', 'true');
}

/**
 * Check and show headphone warning
 */
async function checkHeadphoneWarning() {
    // Don't show if already dismissed
    if (localStorage.getItem('headphoneWarningDismissed') === 'true') {
        return;
    }
    
    // Check if user has headphones (heuristic)
    const hasHeadphones = await app.livekitVoice?.detectHeadphones?.() || false;
    
    // Show warning if no headphones detected
    if (!hasHeadphones && app.elements.headphoneWarning) {
        app.elements.headphoneWarning.classList.remove('hidden');
    }
}

/**
 * Update mobile room name
 */
function updateMobileRoomName(roomName) {
    if (app.elements.mobileRoomName) {
        app.elements.mobileRoomName.textContent = roomName;
    }
}

/**
 * Open modal
 */
function openModal(modalName) {
    const modal = app.elements[modalName];
    if (modal) {
        modal.classList.add('active');
        
        // Initialize noise settings values when opening settings modal
        if (modalName === 'settingsModal') {
            initNoiseSettings();
        }
    }
}

/**
 * Initialize noise suppression settings from LiveKit client
 */
function initNoiseSettings() {
    if (app.livekitVoice) {
        const settings = app.livekitVoice.audioSettings;
        
        // Set checkbox states
        if (app.elements.noiseSuppression) {
            app.elements.noiseSuppression.checked = settings.noiseSuppression;
        }
        if (app.elements.echoCancellation) {
            app.elements.echoCancellation.checked = settings.echoCancellation;
        }
        if (app.elements.noiseGate) {
            app.elements.noiseGate.checked = settings.noiseGateEnabled;
        }
        if (app.elements.noiseGateThreshold) {
            app.elements.noiseGateThreshold.value = settings.noiseGateThreshold;
        }
        if (app.elements.noiseGateValue) {
            app.elements.noiseGateValue.textContent = `${settings.noiseGateThreshold} dB`;
        }
    } else {
        // Set default values if LiveKit isn't connected yet
        if (app.elements.noiseGateValue) {
            app.elements.noiseGateValue.textContent = '-50 dB';
        }
    }
}

/**
 * Close all modals
 */
function closeAllModals() {
    document.querySelectorAll('.modal').forEach(modal => {
        if (modal.id !== 'login-modal' || app.user) {
            modal.classList.remove('active');
        }
    });
}

/**
 * Show login error
 */
function showLoginError(message) {
    app.elements.loginError.textContent = message;
}

/**
 * Show notification
 */
function showNotification(message, type = 'info') {
    console.log(`[${type.toUpperCase()}] ${message}`);
    // Could implement toast notifications here
}

/**
 * Check for invite code in URL
 */
async function checkInviteCode() {
    const params = new URLSearchParams(window.location.search);
    const inviteCode = params.get('invite');
    
    if (inviteCode) {
        try {
            const response = await fetch(`/api/invite/${inviteCode}`);
            const data = await response.json();
            
            if (response.ok && data.valid) {
                app.currentRoom = data.roomId;
                showNotification(`Invite to ${data.roomName} accepted`);
            }
        } catch (error) {
            console.error('Invalid invite code:', error);
        }
    }
}

/**
 * Handle keyboard shortcuts
 */
function handleKeyDown(e) {
    // Only when logged in
    if (!app.user) return;
    
    // M to toggle mute
    if (e.key.toLowerCase() === 'm' && !e.target.matches('input, textarea')) {
        toggleMute();
    }
    
    // D to toggle deafen
    if (e.key.toLowerCase() === 'd' && !e.target.matches('input, textarea')) {
        toggleDeafen();
    }
    
    // Escape to close modals
    if (e.key === 'Escape') {
        closeAllModals();
    }
}

/**
 * Escape HTML to prevent XSS
 */
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', initializeApp);
