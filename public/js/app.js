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
    unreadMessages: 0,
    
    audioHandler: null,
    mumbleClient: null,
    livekitVoice: null,  // LiveKit SFU for voice
    wakeLock: null,       // Screen Wake Lock
    
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
        roomPasswordModal: document.getElementById('room-password-modal'),
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
        videoBtn: document.getElementById('video-btn'),
        screenShareBtn: document.getElementById('screen-share-btn'),
        disconnectBtn: document.getElementById('disconnect-btn'),
        connectionIndicator: document.getElementById('connection-indicator'),
        connectionText: document.getElementById('connection-text'),
        
        // Voice and Video grid
        voiceGrid: document.getElementById('voice-grid'),
        videoGrid: document.getElementById('video-grid'),
        
        // Chat
        chatForm: document.getElementById('chat-form'),
        chatInput: document.getElementById('chat-input'),
        chatMessages: document.getElementById('chat-messages'),
        chatSidebar: document.getElementById('chat-sidebar'),
        toggleChatBtn: document.getElementById('toggle-chat-btn'),
        chatToggleBtn: document.getElementById('chat-toggle-btn'),
        unreadBadge: document.getElementById('unread-badge'),
        
        // Create room
        createRoomBtn: document.getElementById('create-room-btn'),
        createRoomForm: document.getElementById('create-room-form'),
        roomNameInput: document.getElementById('room-name-input'),
        roomDescriptionInput: document.getElementById('room-description-input'),
        roomPasswordInput: document.getElementById('room-password-input'),
        roomMaxUsers: document.getElementById('room-max-users'),
        
        // Room password modal
        roomPasswordForm: document.getElementById('room-password-form'),
        roomPasswordRoomId: document.getElementById('room-password-room-id'),
        roomPasswordJoinInput: document.getElementById('join-room-password-input'),
        roomPasswordError: document.getElementById('room-password-error'),
        roomPasswordMessage: document.getElementById('room-password-message'),
        
        // Settings
        settingsBtn: document.getElementById('settings-btn'),
        inputDevice: document.getElementById('input-device'),
        outputDevice: document.getElementById('output-device'),
        videoDevice: document.getElementById('video-device'),
        videoPreview: document.getElementById('video-preview'),
        videoPreviewContainer: document.getElementById('video-preview-container'),
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
    app.elements.videoBtn?.addEventListener('click', toggleVideo);
    app.elements.screenShareBtn?.addEventListener('click', toggleScreenShare);
    app.elements.disconnectBtn.addEventListener('click', handleDisconnect);
    
    // Chat
    app.elements.chatForm.addEventListener('submit', handleChatSubmit);
    app.elements.toggleChatBtn?.addEventListener('click', toggleChat);
    app.elements.chatToggleBtn?.addEventListener('click', toggleChat);
    
    // Create room
    app.elements.createRoomBtn.addEventListener('click', () => openModal('createRoomModal'));
    app.elements.createRoomForm.addEventListener('submit', handleCreateRoom);
    
    // Room password
    app.elements.roomPasswordForm?.addEventListener('submit', handleRoomPasswordSubmit);
    
    // Settings
    app.elements.settingsBtn.addEventListener('click', () => openModal('settingsModal'));
    app.elements.mobileSettingsBtn?.addEventListener('click', () => openModal('settingsModal'));
    app.elements.inputVolume.addEventListener('input', handleInputVolumeChange);
    app.elements.outputVolume.addEventListener('input', handleOutputVolumeChange);
    app.elements.vadThreshold.addEventListener('input', handleVADThresholdChange);
    app.elements.inputDevice.addEventListener('change', handleInputDeviceChange);
    app.elements.outputDevice?.addEventListener('change', handleOutputDeviceChange);
    app.elements.videoDevice?.addEventListener('change', handleVideoDeviceChange);
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
    const serverPassword = document.getElementById('server-password-input')?.value || '';
    
    if (!username) {
        showLoginError('Please enter a username');
        return;
    }
    
    if (!serverPassword) {
        showLoginError('Please enter the server password');
        return;
    }
    
    try {
        showLoginError(''); // Clear any previous error
        
        // Register user with API
        const response = await fetch('/api/users/register', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name: username, serverPassword })
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
        
        // If user came via invite link, join that room
        // Otherwise, show room list for user to select (no auto-join)
        if (app.currentRoom) {
            joinRoom(app.currentRoom);
        } else {
            // User must select a channel - update UI to reflect no room
            updateActiveRoom('No Channel');
            updateVoiceGrid();
            showNotification('Select a channel to join', 'info');
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
        // Refresh room list to update user counts
        loadRooms();
    };
    
    app.mumbleClient.onUserLeave = (user) => {
        removeUserFromList(user.id);
        removeUserFromVoiceGrid(user.id);
        if (user.name) {
            showNotification(`${user.name} left`);
        }
        // Refresh room list to update user counts
        loadRooms();
    };
    
    app.mumbleClient.onUserSpeaking = (user) => {
        updateUserSpeakingState(user.id, user.isSpeaking);
    };
    
    app.mumbleClient.onStateChanged = (userId, isMuted, isDeafened) => {
        updateUserMutedState(userId, isMuted, isDeafened);
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
        // Fetch users in current room if we're in one
        const url = app.currentRoom ? `/api/users?roomId=${app.currentRoom}` : '/api/users';
        const response = await fetch(url);
        app.users = await response.json();
        
        // Ensure current user is in the list if they're in the room
        if (app.user && app.currentRoom && app.user.roomId === app.currentRoom) {
            const selfInList = app.users.find(u => u.id === app.user.id);
            if (!selfInList) {
                app.users.push({
                    id: app.user.id,
                    name: app.user.name,
                    roomId: app.user.roomId,
                    isMuted: app.user.isMuted || false,
                    isDeafened: app.user.isDeafened || false,
                    isSpeaking: false
                });
            }
        }
        
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
        
        // Show lock icon for password-protected rooms
        const lockIcon = room.isPasswordProtected ? `
            <svg class="lock-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" style="width: 14px; height: 14px; color: var(--accent); margin-left: 4px;">
                <rect x="3" y="11" width="18" height="11" rx="2" ry="2"/>
                <path d="M7 11V7a5 5 0 0 1 10 0v4"/>
            </svg>
        ` : '';
        
        li.innerHTML = `
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
            </svg>
            <div class="room-item-info">
                <span class="room-item-name">${escapeHtml(room.name)}${lockIcon}</span>
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
    
    // Get current room (prefer app.currentRoom, fall back to user's roomId)
    const currentRoomId = app.currentRoom || app.user?.roomId;
    
    // Filter users in current room (only show users who have joined a room)
    const roomUsers = app.users.filter(u => u.roomId && u.roomId === currentRoomId);
    
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
async function joinRoom(roomId, password = null) {
    try {
        const response = await fetch(`/api/users/${app.user.id}/join/${roomId}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ password })
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            // If password required, show password modal
            if (data.requiresPassword || response.status === 401) {
                showPasswordModal(roomId, data.roomName || 'this room');
                return;
            }
            throw new Error(data.error);
        }
        
        // Update state
        app.user.roomId = roomId;
        app.currentRoom = roomId;
        
        // Update UI
        updateActiveRoom(data.roomName);
        
        // Close sidebar on mobile after joining room
        closeSidebar();
        
        // Reload users and rooms (for user counts)
        await loadUsers();
        await loadRooms();
        
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
        
        // Request Wake Lock to prevent screen from sleeping during call
        requestWakeLock();
        
        showNotification(`Joined ${data.roomName}`, 'success');
        
    } catch (error) {
        console.error('Failed to join room:', error);
        showNotification(error.message, 'error');
    }
}

/**
 * Show password modal for protected room
 */
function showPasswordModal(roomId, roomName) {
    const modal = app.elements.roomPasswordModal;
    if (!modal) return;
    
    // Reset modal state
    app.elements.roomPasswordRoomId.value = roomId;
    app.elements.roomPasswordJoinInput.value = '';
    app.elements.roomPasswordError.textContent = '';
    app.elements.roomPasswordMessage.textContent = `Enter the password to join "${roomName}".`;
    
    modal.classList.add('active');
    app.elements.roomPasswordJoinInput.focus();
}

/**
 * Handle room password form submission
 */
async function handleRoomPasswordSubmit(e) {
    e.preventDefault();
    
    const roomId = app.elements.roomPasswordRoomId.value;
    const password = app.elements.roomPasswordJoinInput.value;
    
    if (!password) {
        app.elements.roomPasswordError.textContent = 'Please enter the password';
        return;
    }
    
    try {
        const response = await fetch(`/api/users/${app.user.id}/join/${roomId}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ password })
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            app.elements.roomPasswordError.textContent = data.error || 'Incorrect password';
            return;
        }
        
        // Success - close modal and complete join
        closeAllModals();
        
        // Update state
        app.user.roomId = roomId;
        
        // Update UI
        updateActiveRoom(data.roomName);
        closeSidebar();
        await loadUsers();
        await loadRooms();  // Refresh room list for user counts
        
        document.querySelectorAll('.room-item').forEach(item => {
            item.classList.toggle('active', item.dataset.roomId === roomId);
        });
        
        app.mumbleClient?.joinChannel(roomId);
        updateVoiceGrid();
        initializeLiveKitVoice(roomId);
        
        showNotification(`Joined ${data.roomName}`, 'success');
        
    } catch (error) {
        console.error('Failed to join room with password:', error);
        app.elements.roomPasswordError.textContent = 'Failed to join room';
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
            // Remove their video tile if they had one
            removeVideoTile(participant.id);
        };
        
        app.livekitVoice.onSpeakingChanged = (speakingIds) => {
            // Update speaking indicators for all users in app.users
            app.users.forEach(user => {
                const isSpeaking = speakingIds.includes(user.id);
                updateUserSpeakingState(user.id, isSpeaking);
            });
            
            // Also update local user if not in app.users
            if (app.user) {
                const localSpeaking = speakingIds.includes(app.user.id);
                updateUserSpeakingState(app.user.id, localSpeaking);
            }
            
            // Also directly update all voice cards to clear speaking state
            document.querySelectorAll('.voice-card').forEach(card => {
                const userId = card.dataset.userId;
                const isSpeaking = speakingIds.includes(userId);
                card.classList.toggle('speaking', isSpeaking);
                const avatar = card.querySelector('.user-avatar');
                avatar?.classList.toggle('speaking', isSpeaking);
            });
        };
        
        app.livekitVoice.onStateChanged = (userId, isMuted, isDeafened) => {
            updateUserMutedState(userId, isMuted, isDeafened);
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
        
        // Handle video track subscriptions
        app.livekitVoice.onVideoTrackSubscribed = (track, participant) => {
            console.log('Video: track subscribed from:', participant.identity);
            addRemoteVideoTile(track, participant);
        };
        
        app.livekitVoice.onVideoTrackUnsubscribed = (track, participant) => {
            console.log('Video: track unsubscribed from:', participant.identity);
            removeVideoTile(participant.identity);
        };
        
        // Handle screen share track subscriptions
        app.livekitVoice.onScreenTrackSubscribed = (track, participant) => {
            console.log('Screen: track subscribed from:', participant.identity);
            addRemoteScreenShareTile(track, participant);
        };
        
        app.livekitVoice.onScreenTrackUnsubscribed = (track, participant) => {
            console.log('Screen: track unsubscribed from:', participant.identity);
            removeVideoTile(`${participant.identity}-screen`);
        };
        
        // Handle screen share state changes (for button UI)
        app.livekitVoice.onScreenShareStateChanged = (isSharing) => {
            const screenShareBtn = app.elements.screenShareBtn;
            if (screenShareBtn) {
                screenShareBtn.classList.toggle('active', isSharing);
                screenShareBtn.querySelector('.icon-screen-share')?.classList.toggle('hidden', isSharing);
                screenShareBtn.querySelector('.icon-screen-share-off')?.classList.toggle('hidden', !isSharing);
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
    
    // Check if user is in a room
    if (!app.user?.roomId) {
        grid.innerHTML = `
            <div class="voice-placeholder">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
                </svg>
                <p>Select a channel to start talking</p>
            </div>
        `;
        return;
    }
    
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
    card.className = `voice-card ${user.isSpeaking ? 'speaking' : ''} ${user.isMuted ? 'muted' : ''}`;
    card.dataset.userId = user.id;
    
    card.innerHTML = `
        <div class="user-avatar ${user.isSpeaking ? 'speaking' : ''}">
            <span>${initial}</span>
        </div>
        <div class="user-name">${escapeHtml(user.name)}${isMe ? ' (you)' : ''}</div>
        <div class="user-status-icons">
            ${user.isMuted ? '<span class="status-icon muted" title="Muted">🔇</span>' : ''}
            ${user.isDeafened ? '<span class="status-icon deafened" title="Deafened">🔕</span>' : ''}
        </div>
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
 * Update user muted/deafened state in UI
 */
function updateUserMutedState(userId, isMuted, isDeafened) {
    console.log('[UI] Updating mute state for user:', userId, 'muted:', isMuted, 'deafened:', isDeafened);
    
    // Find user in app.users array
    const user = app.users.find(u => u.id === userId);
    if (user) {
        user.isMuted = isMuted;
        user.isDeafened = isDeafened;
    }
    
    // Update in user list - rebuild the status icons
    const userListItem = document.querySelector(`.user-item[data-user-id="${userId}"]`);
    if (userListItem) {
        // Update status indicator (dot)
        const statusIndicator = userListItem.querySelector('.status-indicator');
        if (statusIndicator) {
            statusIndicator.className = `status-indicator ${isMuted ? 'muted' : 'online'}`;
        }
        
        // Rebuild the status icons container
        const statusContainer = userListItem.querySelector('.user-item-status');
        if (statusContainer) {
            let iconsHtml = '';
            if (isMuted) {
                iconsHtml += '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="mute-icon"><line x1="1" y1="1" x2="23" y2="23"/><path d="M9 9v3a3 3 0 0 0 5.12 2.12"/></svg>';
            }
            if (isDeafened) {
                iconsHtml += '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="deafen-icon"><line x1="1" y1="1" x2="23" y2="23"/><path d="M3 18v-6a9 9 0 0 1 14.77-6.94"/></svg>';
            }
            statusContainer.innerHTML = iconsHtml;
        }
    }
    
    // Update in voice grid
    const voiceCard = document.querySelector(`.voice-card[data-user-id="${userId}"]`);
    if (voiceCard) {
        voiceCard.classList.toggle('muted', isMuted);
        voiceCard.classList.toggle('deafened', isDeafened);
        
        // Update status icons in voice card
        const statusIcons = voiceCard.querySelector('.user-status-icons');
        if (statusIcons) {
            let iconsHtml = '';
            if (isMuted) {
                iconsHtml += '<span class="status-icon muted" title="Muted">🔇</span>';
            }
            if (isDeafened) {
                iconsHtml += '<span class="status-icon deafened" title="Deafened">🔕</span>';
            }
            statusIcons.innerHTML = iconsHtml;
        }
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
        
        // If unmuting, also undeafen
        if (!isMuted && app.livekitVoice.isDeafened) {
            app.livekitVoice.setDeafened(false);
            app.elements.deafenBtn.classList.remove('active');
            app.elements.deafenBtn.querySelector('.icon-headphones').classList.remove('hidden');
            app.elements.deafenBtn.querySelector('.icon-headphones-off').classList.add('hidden');
        }
    } else if (app.audioHandler) {
        isMuted = app.audioHandler.toggleMute();
    }
    
    app.elements.muteBtn.classList.toggle('active', isMuted);
    app.elements.muteBtn.querySelector('.icon-mic').classList.toggle('hidden', isMuted);
    app.elements.muteBtn.querySelector('.icon-mic-off').classList.toggle('hidden', !isMuted);
    
    // Update server with both states
    const isDeafened = app.livekitVoice?.isDeafened || false;
    await fetch(`/api/users/${app.user.id}/state`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isMuted, isDeafened })
    });
}

/**
 * Toggle deafen
 */
async function toggleDeafen() {
    let isDeafened = false;
    let isMuted = false;
    
    // Control LiveKit if available
    if (app.livekitVoice) {
        isDeafened = app.livekitVoice.toggleDeafen();
        
        // If deafening, also mute mic
        if (isDeafened) {
            if (!app.livekitVoice.isMuted) {
                app.livekitVoice.setMuted(true);
            }
            isMuted = true;
        } else {
            // If undeafening, also unmute mic
            app.livekitVoice.setMuted(false);
            isMuted = false;
        }
    } else if (app.audioHandler) {
        isDeafened = app.audioHandler.toggleDeafen();
        isMuted = isDeafened;
    }
    
    // Update deafen button UI
    app.elements.deafenBtn.classList.toggle('active', isDeafened);
    app.elements.deafenBtn.querySelector('.icon-headphones').classList.toggle('hidden', isDeafened);
    app.elements.deafenBtn.querySelector('.icon-headphones-off').classList.toggle('hidden', !isDeafened);
    
    // Update mute button UI
    app.elements.muteBtn.classList.toggle('active', isMuted);
    app.elements.muteBtn.querySelector('.icon-mic').classList.toggle('hidden', isMuted);
    app.elements.muteBtn.querySelector('.icon-mic-off').classList.toggle('hidden', !isMuted);
    
    // Update server with both states
    await fetch(`/api/users/${app.user.id}/state`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ isDeafened, isMuted })
    });
}

/**
 * Toggle video
 */
async function toggleVideo() {
    if (!app.livekitVoice) {
        showNotification('Voice not connected', 'error');
        return;
    }
    
    const videoBtn = app.elements.videoBtn;
    if (!videoBtn) return;
    
    // Toggle video
    const success = await app.livekitVoice.toggleVideo();
    
    if (success) {
        const isVideoEnabled = app.livekitVoice.isVideoEnabled;
        videoBtn.classList.toggle('active', isVideoEnabled);
        videoBtn.querySelector('.icon-video')?.classList.toggle('hidden', isVideoEnabled);
        videoBtn.querySelector('.icon-video-off')?.classList.toggle('hidden', !isVideoEnabled);
        
        // Update local video preview in video grid
        if (isVideoEnabled && app.livekitVoice.localVideoTrack) {
            addLocalVideoTile();
        } else {
            removeVideoTile(app.user.id);
        }
        
        showNotification(isVideoEnabled ? '📹 Video enabled' : '📹 Video disabled', 'success');
    }
}

/**
 * Add local video tile to grid
 */
function addLocalVideoTile() {
    if (!app.livekitVoice?.localVideoTrack) return;
    
    const videoGrid = app.elements.videoGrid;
    if (!videoGrid) return;
    
    // Remove existing local tile
    removeVideoTile(app.user.id);
    
    const tile = document.createElement('div');
    tile.className = 'video-tile local';
    tile.id = `video-tile-${app.user.id}`;
    tile.dataset.participantId = app.user.id;
    
    const video = document.createElement('video');
    video.id = `video-${app.user.id}`;
    video.autoplay = true;
    video.muted = true; // Local video is always muted
    video.playsInline = true;
    
    // Attach the local video track
    app.livekitVoice.localVideoTrack.attach(video);
    
    const nameLabel = document.createElement('div');
    nameLabel.className = 'video-name';
    nameLabel.textContent = `${app.user.name} (You)`;
    
    tile.appendChild(video);
    tile.appendChild(nameLabel);
    videoGrid.appendChild(tile);
    
    // Show video grid
    videoGrid.classList.remove('hidden');
    updateVideoGridLayout();
}

/**
 * Add remote video tile to grid
 */
function addRemoteVideoTile(track, participant) {
    const videoGrid = app.elements.videoGrid;
    if (!videoGrid) return;
    
    // Remove existing tile for this participant
    removeVideoTile(participant.identity);
    
    const tile = document.createElement('div');
    tile.className = 'video-tile';
    tile.id = `video-tile-${participant.identity}`;
    tile.dataset.participantId = participant.identity;
    
    const video = document.createElement('video');
    video.id = `video-${participant.identity}`;
    video.autoplay = true;
    video.playsInline = true;
    
    // Attach the remote video track
    track.attach(video);
    
    const nameLabel = document.createElement('div');
    nameLabel.className = 'video-name';
    nameLabel.textContent = participant.name || participant.identity;
    
    tile.appendChild(video);
    tile.appendChild(nameLabel);
    videoGrid.appendChild(tile);
    
    // Show video grid
    videoGrid.classList.remove('hidden');
    updateVideoGridLayout();
}

/**
 * Remove video tile from grid
 */
function removeVideoTile(participantId) {
    const tile = document.getElementById(`video-tile-${participantId}`);
    if (tile) {
        const video = tile.querySelector('video');
        if (video) {
            // Detach tracks
            video.srcObject = null;
        }
        tile.remove();
    }
    
    // Hide grid if empty
    const videoGrid = app.elements.videoGrid;
    if (videoGrid && videoGrid.children.length === 0) {
        videoGrid.classList.add('hidden');
    }
    
    updateVideoGridLayout();
}

/**
 * Update video grid layout based on number of participants
 */
function updateVideoGridLayout() {
    const videoGrid = app.elements.videoGrid;
    if (!videoGrid) return;
    
    const count = videoGrid.children.length;
    
    // Remove previous layout classes
    videoGrid.classList.remove('grid-1', 'grid-2', 'grid-3', 'grid-4', 'grid-many');
    
    if (count === 0) {
        videoGrid.classList.add('hidden');
    } else if (count === 1) {
        videoGrid.classList.add('grid-1');
    } else if (count === 2) {
        videoGrid.classList.add('grid-2');
    } else if (count <= 4) {
        videoGrid.classList.add('grid-4');
    } else {
        videoGrid.classList.add('grid-many');
    }
}

/**
 * Toggle screen sharing
 */
async function toggleScreenShare() {
    if (!app.livekitVoice) {
        showNotification('Voice not connected', 'error');
        return;
    }
    
    const screenShareBtn = app.elements.screenShareBtn;
    if (!screenShareBtn) return;
    
    try {
        // Toggle screen share
        const success = await app.livekitVoice.toggleScreenShare();
        
        if (success !== undefined) {
            const isScreenSharing = app.livekitVoice.isScreenSharing;
            screenShareBtn.classList.toggle('active', isScreenSharing);
            screenShareBtn.querySelector('.icon-screen-share')?.classList.toggle('hidden', isScreenSharing);
            screenShareBtn.querySelector('.icon-screen-share-off')?.classList.toggle('hidden', !isScreenSharing);
            
            // Add/remove screen share tile
            if (isScreenSharing && app.livekitVoice.localScreenTrack) {
                addLocalScreenShareTile();
            } else {
                removeVideoTile(`${app.user.id}-screen`);
            }
            
            showNotification(isScreenSharing ? '🖥️ Screen sharing started' : '🖥️ Screen sharing stopped', 'success');
        }
    } catch (error) {
        console.error('Screen share error:', error);
        showNotification('Failed to share screen: ' + error.message, 'error');
    }
}

/**
 * Add local screen share tile to video grid
 */
function addLocalScreenShareTile() {
    if (!app.livekitVoice?.localScreenTrack) return;
    
    const videoGrid = app.elements.videoGrid;
    if (!videoGrid) return;
    
    // Remove existing screen share tile
    removeVideoTile(`${app.user.id}-screen`);
    
    const tile = document.createElement('div');
    tile.className = 'video-tile local screen-share';
    tile.id = `video-tile-${app.user.id}-screen`;
    tile.dataset.participantId = `${app.user.id}-screen`;
    
    const video = document.createElement('video');
    video.id = `video-${app.user.id}-screen`;
    video.autoplay = true;
    video.muted = true;
    video.playsInline = true;
    
    // Attach the local screen share track
    app.livekitVoice.localScreenTrack.attach(video);
    
    const nameLabel = document.createElement('div');
    nameLabel.className = 'video-name';
    nameLabel.innerHTML = `<span class="screen-share-icon">🖥️</span> ${app.user.name} (Screen)`;
    
    tile.appendChild(video);
    tile.appendChild(nameLabel);
    videoGrid.appendChild(tile);
    
    // Show video grid
    videoGrid.classList.remove('hidden');
    updateVideoGridLayout();
}

/**
 * Add remote screen share tile to video grid
 */
function addRemoteScreenShareTile(track, participant) {
    const videoGrid = app.elements.videoGrid;
    if (!videoGrid) return;
    
    // Remove existing screen share tile for this participant
    removeVideoTile(`${participant.identity}-screen`);
    
    const tile = document.createElement('div');
    tile.className = 'video-tile screen-share featured';  // Featured class makes it larger
    tile.id = `video-tile-${participant.identity}-screen`;
    tile.dataset.participantId = `${participant.identity}-screen`;
    
    const video = document.createElement('video');
    video.id = `video-${participant.identity}-screen`;
    video.autoplay = true;
    video.playsInline = true;
    
    // Attach the remote screen share track
    track.attach(video);
    
    const nameLabel = document.createElement('div');
    nameLabel.className = 'video-name';
    nameLabel.innerHTML = `<span class="screen-share-icon">🖥️</span> ${participant.name || participant.identity} (Screen)`;
    
    tile.appendChild(video);
    tile.appendChild(nameLabel);
    
    // Insert screen share tiles at the beginning (featured position)
    videoGrid.insertBefore(tile, videoGrid.firstChild);
    
    // Show video grid
    videoGrid.classList.remove('hidden');
    updateVideoGridLayout();
    
    showNotification(`${participant.name || participant.identity} is sharing their screen`, 'info');
}

/**
 * Request Wake Lock to prevent screen from sleeping during call
 * Uses native Wake Lock API with fallback for unsupported browsers
 */
async function requestWakeLock() {
    try {
        // Check if Wake Lock API is supported
        if ('wakeLock' in navigator) {
            // Release existing lock first
            if (app.wakeLock) {
                await app.wakeLock.release();
            }
            
            // Request a new wake lock
            app.wakeLock = await navigator.wakeLock.request('screen');
            
            console.log('🔒 Wake Lock acquired - screen will stay on during call');
            
            // Handle visibility change - re-acquire wake lock when page becomes visible
            app.wakeLock.addEventListener('release', () => {
                console.log('🔓 Wake Lock released');
            });
            
            // Re-acquire wake lock on visibility change
            document.addEventListener('visibilitychange', handleVisibilityChange);
            
        } else {
            // Fallback: Use a hidden video element to keep screen awake (iOS workaround)
            console.log('⚠️ Wake Lock API not supported, using video fallback');
            enableNoSleepFallback();
        }
    } catch (error) {
        console.warn('Wake Lock request failed, trying fallback:', error.message);
        // Fallback for browsers that support Wake Lock but fail (e.g., battery saver mode)
        enableNoSleepFallback();
    }
}

/**
 * NoSleep fallback using a silent video loop for browsers without Wake Lock API
 */
function enableNoSleepFallback() {
    // Remove existing fallback if any
    disableNoSleepFallback();
    
    // Create a tiny, silent video that loops to keep the screen awake
    const video = document.createElement('video');
    video.id = 'nosleep-video';
    video.setAttribute('playsinline', '');
    video.setAttribute('muted', '');
    video.setAttribute('loop', '');
    video.style.cssText = 'position:fixed;top:-1px;left:-1px;width:1px;height:1px;opacity:0.01;pointer-events:none;';
    
    // Use a tiny webm video (base64 encoded 1x1 pixel, ~1 second)
    // This is a minimal valid webm file
    video.src = 'data:video/webm;base64,GkXfo59ChoEBQveBAULygQRC84EIQoKEd2VibUKHgQRChYECGFOAZwH/////////FUmpZpkq17GDD0JATYCGQ2hyb21lV0WGQ2hyb21lFlSua7+uvdeBAXPFhg5LdkFtYXZpbmdAQ0BCwAEAAAAAAAARTZt0pJKJjsKJj7LNjJCJHPEAAAAAAABoZ2FuAAAAAAAAAABIYWxleSBEaWdnaW5zAAAAAAAAAAAAAAAAZW5jb2RlZCBieSBMYXZjIDU4LjEzNC4xMDABAAAAAAAAFgA//////////xOhggBAAABFBgRERkdISktMTU5PUFFSU1RVVldYWVpbXF1eX2BhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ent8fX5/gIGCg4SFhoeIiYqLjI2Oj5CRkpOUlZaXmJmam5ydnp+goaKjpKWmp6ipqqusra6vsLGys7S1tre4ubq7vL2+v8DBwsPExcbHyMnKy8zNzs/Q0dLT1NXW19jZ2tvc3d7f4OHi4+Tl5ufo6err7O3u7/Dx8vP09fb3+Pn6+/z9/v8A';
    
    document.body.appendChild(video);
    
    // Play the video
    const playPromise = video.play();
    if (playPromise) {
        playPromise.catch(() => {
            // Autoplay blocked, will work after user interaction
            console.log('NoSleep video autoplay blocked, will activate on interaction');
        });
    }
    
    // Also start silent audio context to prevent tab throttling
    startSilentAudio();
    
    console.log('🔒 NoSleep fallback enabled');
}

/**
 * Start silent audio playback to prevent browser from throttling the tab
 * Browsers don't throttle tabs that are playing audio
 */
let silentAudioContext = null;
let silentAudioInterval = null;

function startSilentAudio() {
    stopSilentAudio();
    
    try {
        silentAudioContext = new (window.AudioContext || window.webkitAudioContext)();
        
        // Create a silent oscillator
        const oscillator = silentAudioContext.createOscillator();
        const gainNode = silentAudioContext.createGain();
        
        // Set gain to essentially zero (inaudible)
        gainNode.gain.value = 0.001;
        
        oscillator.connect(gainNode);
        gainNode.connect(silentAudioContext.destination);
        
        oscillator.start();
        
        // Periodically "tickle" the audio context to keep it alive
        silentAudioInterval = setInterval(() => {
            if (silentAudioContext && silentAudioContext.state === 'suspended') {
                silentAudioContext.resume();
            }
        }, 10000);
        
        console.log('🔊 Silent audio context started (prevents tab throttling)');
    } catch (e) {
        console.warn('Could not start silent audio:', e);
    }
}

function stopSilentAudio() {
    if (silentAudioInterval) {
        clearInterval(silentAudioInterval);
        silentAudioInterval = null;
    }
    
    if (silentAudioContext) {
        try {
            silentAudioContext.close();
        } catch (e) {
            // Ignore
        }
        silentAudioContext = null;
    }
}

/**
 * Disable NoSleep fallback
 */
function disableNoSleepFallback() {
    const video = document.getElementById('nosleep-video');
    if (video) {
        video.pause();
        video.remove();
        console.log('🔓 NoSleep fallback disabled');
    }
    
    stopSilentAudio();
}

/**
 * Release Wake Lock
 */
async function releaseWakeLock() {
    try {
        if (app.wakeLock) {
            await app.wakeLock.release();
            app.wakeLock = null;
            console.log('🔓 Wake Lock released - screen can sleep now');
        }
        
        // Also disable fallback if active
        disableNoSleepFallback();
        
        // Remove visibility change handler
        document.removeEventListener('visibilitychange', handleVisibilityChange);
        
    } catch (error) {
        console.warn('Wake Lock release failed:', error);
    }
}

/**
 * Handle visibility change - re-acquire wake lock when page becomes visible
 */
async function handleVisibilityChange() {
    if (document.visibilityState === 'visible' && app.user?.roomId && app.livekitVoice?.isConnected) {
        // Re-acquire wake lock when coming back to the app
        if (!app.wakeLock || app.wakeLock.released) {
            try {
                app.wakeLock = await navigator.wakeLock.request('screen');
                console.log('🔒 Wake Lock re-acquired after visibility change');
            } catch (error) {
                console.warn('Wake Lock re-acquisition failed:', error);
            }
        }
    }
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
        
        // Release Wake Lock
        releaseWakeLock();
        
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
        <span class="sender">${escapeHtml(message.userName || message.sender || 'Unknown')}</span>
        <span class="time">${time}</span>
        <div class="content">${escapeHtml(message.content)}</div>
    `;
    
    messagesContainer.appendChild(div);
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
    
    // Update unread count if chat is closed and message is from someone else
    const isChatOpen = app.elements.chatSidebar?.classList.contains('open');
    const isOwnMessage = message.userId === app.user?.id;
    if (!isChatOpen && !isOwnMessage) {
        app.unreadMessages++;
        updateUnreadBadge();
    }
}

/**
 * Handle create room
 */
async function handleCreateRoom(e) {
    e.preventDefault();
    
    const name = app.elements.roomNameInput.value.trim();
    const description = app.elements.roomDescriptionInput.value.trim();
    const password = app.elements.roomPasswordInput?.value?.trim() || '';
    const maxUsers = parseInt(app.elements.roomMaxUsers.value) || 25;
    
    if (!name) return;
    
    try {
        const response = await fetch('/api/rooms', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name, description, password, maxUsers })
        });
        
        const data = await response.json();
        
        if (!response.ok) {
            throw new Error(data.error);
        }
        
        // Close modal
        closeAllModals();
        
        // Reload rooms
        await loadRooms();
        
        // Join new room (no password needed since we just created it)
        joinRoom(data.id, password);
        
        // Reset form
        app.elements.createRoomForm.reset();
        
        const protectedMsg = data.isPasswordProtected ? ' (password protected)' : '';
        showNotification(`Room "${data.name}" created${protectedMsg}`, 'success');
        
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
 * Handle video device change
 */
async function handleVideoDeviceChange() {
    const deviceId = app.elements.videoDevice?.value;
    
    if (app.livekitVoice) {
        await app.livekitVoice.changeVideoDevice(deviceId || null);
        console.log('[Video] Camera changed to:', deviceId || 'default');
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
 * Toggle chat sidebar
 */
function toggleChat() {
    const chatSidebar = app.elements.chatSidebar;
    if (!chatSidebar) return;
    
    const isOpen = chatSidebar.classList.toggle('open');
    
    // Update button active state
    app.elements.chatToggleBtn?.classList.toggle('active', isOpen);
    
    // Reset unread count when opening
    if (isOpen) {
        app.unreadMessages = 0;
        updateUnreadBadge();
        // Focus input when opening
        setTimeout(() => app.elements.chatInput?.focus(), 100);
    }
}

/**
 * Update unread message badge
 */
function updateUnreadBadge() {
    const badge = app.elements.unreadBadge;
    if (!badge) return;
    
    if (app.unreadMessages > 0) {
        badge.textContent = app.unreadMessages > 99 ? '99+' : app.unreadMessages;
        badge.classList.remove('hidden');
    } else {
        badge.classList.add('hidden');
    }
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
            populateDevices();
        }
    }
}

/**
 * Populate audio and video device dropdowns
 */
async function populateDevices() {
    try {
        const devices = await navigator.mediaDevices.enumerateDevices();
        
        // Populate microphones
        const inputSelect = app.elements.inputDevice;
        if (inputSelect) {
            const currentValue = inputSelect.value;
            inputSelect.innerHTML = '<option value="">Default Microphone</option>';
            devices.filter(d => d.kind === 'audioinput').forEach(device => {
                const option = document.createElement('option');
                option.value = device.deviceId;
                option.textContent = device.label || `Microphone ${device.deviceId.slice(0, 8)}`;
                inputSelect.appendChild(option);
            });
            inputSelect.value = currentValue;
        }
        
        // Populate speakers
        const outputSelect = app.elements.outputDevice;
        if (outputSelect) {
            const currentValue = outputSelect.value;
            outputSelect.innerHTML = '<option value="">Default Speakers</option>';
            devices.filter(d => d.kind === 'audiooutput').forEach(device => {
                const option = document.createElement('option');
                option.value = device.deviceId;
                option.textContent = device.label || `Speakers ${device.deviceId.slice(0, 8)}`;
                outputSelect.appendChild(option);
            });
            outputSelect.value = currentValue;
        }
        
        // Populate cameras
        const videoSelect = app.elements.videoDevice;
        if (videoSelect) {
            const currentValue = videoSelect.value;
            videoSelect.innerHTML = '<option value="">Default Camera</option>';
            devices.filter(d => d.kind === 'videoinput').forEach(device => {
                const option = document.createElement('option');
                option.value = device.deviceId;
                option.textContent = device.label || `Camera ${device.deviceId.slice(0, 8)}`;
                videoSelect.appendChild(option);
            });
            videoSelect.value = currentValue;
        }
    } catch (error) {
        console.error('Failed to enumerate devices:', error);
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
