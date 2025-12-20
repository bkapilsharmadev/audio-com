/**
 * AudioHandler - Manages microphone input and audio output
 * Handles WebRTC audio streams and voice activity detection
 */
class AudioHandler {
    constructor() {
        this.audioContext = null;
        this.mediaStream = null;
        this.analyser = null;
        this.microphone = null;
        this.gainNode = null;
        
        this.isMuted = false;
        this.isDeafened = false;
        this.isSpeaking = false;
        
        this.inputVolume = 1.0;
        this.outputVolume = 1.0;
        this.vadThreshold = 0.02; // Voice activity detection threshold
        
        this.onSpeakingChange = null;
        this.onVolumeLevel = null;
        
        this.vadInterval = null;
        this.audioDevices = {
            inputs: [],
            outputs: []
        };
    }

    /**
     * Initialize audio context and enumerate devices
     */
    async initialize() {
        try {
            // Create audio context
            this.audioContext = new (window.AudioContext || window.webkitAudioContext)();
            
            // Resume audio context if suspended (Chrome autoplay policy)
            if (this.audioContext.state === 'suspended') {
                await this.audioContext.resume();
            }
            
            // Enumerate available devices
            await this.enumerateDevices();
            
            console.log('AudioHandler initialized');
            return true;
        } catch (error) {
            console.error('Failed to initialize AudioHandler:', error);
            throw error;
        }
    }

    /**
     * Enumerate audio input/output devices
     */
    async enumerateDevices() {
        try {
            const devices = await navigator.mediaDevices.enumerateDevices();
            
            this.audioDevices.inputs = devices.filter(d => d.kind === 'audioinput');
            this.audioDevices.outputs = devices.filter(d => d.kind === 'audiooutput');
            
            console.log('Audio devices:', this.audioDevices);
            return this.audioDevices;
        } catch (error) {
            console.error('Failed to enumerate devices:', error);
            return this.audioDevices;
        }
    }

    /**
     * Request microphone access and start capturing
     * @param {string} deviceId - Optional specific device ID
     */
    async startCapture(deviceId = null) {
        try {
            const constraints = {
                audio: {
                    echoCancellation: true,
                    noiseSuppression: true,
                    autoGainControl: true,
                    ...(deviceId && { deviceId: { exact: deviceId } })
                }
            };
            
            this.mediaStream = await navigator.mediaDevices.getUserMedia(constraints);
            
            // Create audio nodes
            this.microphone = this.audioContext.createMediaStreamSource(this.mediaStream);
            this.gainNode = this.audioContext.createGain();
            this.analyser = this.audioContext.createAnalyser();
            
            this.analyser.fftSize = 256;
            this.analyser.smoothingTimeConstant = 0.8;
            
            // Connect nodes: microphone -> gain -> analyser
            this.microphone.connect(this.gainNode);
            this.gainNode.connect(this.analyser);
            
            // Set initial volume
            this.gainNode.gain.value = this.inputVolume;
            
            // Start voice activity detection
            this.startVAD();
            
            console.log('Microphone capture started');
            return this.mediaStream;
        } catch (error) {
            console.error('Failed to start capture:', error);
            throw error;
        }
    }

    /**
     * Stop microphone capture
     */
    stopCapture() {
        this.stopVAD();
        
        if (this.mediaStream) {
            this.mediaStream.getTracks().forEach(track => track.stop());
            this.mediaStream = null;
        }
        
        if (this.microphone) {
            this.microphone.disconnect();
            this.microphone = null;
        }
        
        if (this.gainNode) {
            this.gainNode.disconnect();
            this.gainNode = null;
        }
        
        if (this.analyser) {
            this.analyser.disconnect();
            this.analyser = null;
        }
        
        console.log('Microphone capture stopped');
    }

    /**
     * Start voice activity detection
     */
    startVAD() {
        if (this.vadInterval) return;
        
        const bufferLength = this.analyser.frequencyBinCount;
        const dataArray = new Uint8Array(bufferLength);
        
        this.vadInterval = setInterval(() => {
            if (!this.analyser || this.isMuted) {
                if (this.isSpeaking) {
                    this.isSpeaking = false;
                    this.onSpeakingChange?.(false);
                }
                return;
            }
            
            this.analyser.getByteFrequencyData(dataArray);
            
            // Calculate average volume
            let sum = 0;
            for (let i = 0; i < bufferLength; i++) {
                sum += dataArray[i];
            }
            const average = sum / bufferLength / 255; // Normalize to 0-1
            
            // Report volume level
            this.onVolumeLevel?.(average);
            
            // Detect speaking based on threshold
            const wasSpeaking = this.isSpeaking;
            this.isSpeaking = average > this.vadThreshold;
            
            if (wasSpeaking !== this.isSpeaking) {
                this.onSpeakingChange?.(this.isSpeaking);
            }
        }, 50); // Check every 50ms
    }

    /**
     * Stop voice activity detection
     */
    stopVAD() {
        if (this.vadInterval) {
            clearInterval(this.vadInterval);
            this.vadInterval = null;
        }
    }

    /**
     * Toggle mute state
     */
    toggleMute() {
        this.isMuted = !this.isMuted;
        
        if (this.gainNode) {
            this.gainNode.gain.value = this.isMuted ? 0 : this.inputVolume;
        }
        
        // Also mute the actual tracks
        if (this.mediaStream) {
            this.mediaStream.getAudioTracks().forEach(track => {
                track.enabled = !this.isMuted;
            });
        }
        
        return this.isMuted;
    }

    /**
     * Toggle deafen state (mute + no audio output)
     */
    toggleDeafen() {
        this.isDeafened = !this.isDeafened;
        
        // When deafening, also mute
        if (this.isDeafened && !this.isMuted) {
            this.toggleMute();
        }
        
        return this.isDeafened;
    }

    /**
     * Set input volume
     * @param {number} volume - Volume from 0 to 1
     */
    setInputVolume(volume) {
        this.inputVolume = Math.max(0, Math.min(1, volume));
        
        if (this.gainNode && !this.isMuted) {
            this.gainNode.gain.value = this.inputVolume;
        }
    }

    /**
     * Set output volume
     * @param {number} volume - Volume from 0 to 1
     */
    setOutputVolume(volume) {
        this.outputVolume = Math.max(0, Math.min(1, volume));
        // This would be applied to played audio elements
    }

    /**
     * Set VAD threshold
     * @param {number} threshold - Threshold from 0 to 1
     */
    setVADThreshold(threshold) {
        this.vadThreshold = Math.max(0, Math.min(0.5, threshold));
    }

    /**
     * Change input device
     * @param {string} deviceId - Device ID to switch to
     */
    async changeInputDevice(deviceId) {
        const wasCapturing = this.mediaStream !== null;
        
        if (wasCapturing) {
            this.stopCapture();
        }
        
        if (wasCapturing) {
            await this.startCapture(deviceId);
        }
    }

    /**
     * Get current audio stats
     */
    getStats() {
        return {
            isMuted: this.isMuted,
            isDeafened: this.isDeafened,
            isSpeaking: this.isSpeaking,
            inputVolume: this.inputVolume,
            outputVolume: this.outputVolume,
            hasStream: this.mediaStream !== null,
            devices: this.audioDevices
        };
    }

    /**
     * Clean up all resources
     */
    destroy() {
        this.stopCapture();
        
        if (this.audioContext) {
            this.audioContext.close();
            this.audioContext = null;
        }
        
        console.log('AudioHandler destroyed');
    }
}

// Export for use
window.AudioHandler = AudioHandler;
