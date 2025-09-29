import Foundation
import PipecatClientIOS
import OSLog

/// An RTVI transport to connect with the Gemini Live WebSocket backend.
public class GeminiLiveWebSocketTransport: Transport {
    
    // MARK: - Public
    
    /// Voice client delegate (used directly by user's code)
    public weak var delegate: PipecatClientDelegate?
    
    /// RTVI inbound message handler (for sending RTVI-style messages to voice client code to handle)
    public var onMessage: ((RTVIMessageInbound) -> Void)?
    
    public required init() {
        self.enableMic = true
        self.enableCam = false
        
        connection = GeminiLiveWebSocketConnection()
        connection.delegate = self
        audioPlayer.delegate = self
        audioRecorder.delegate = self
        audioManager.delegate = self
    }

    // Add this new method after the init
    public func initialize(options: PipecatClientOptions) {
        // Extract what we need from PipecatClientOptions
        self.enableMic = options.enableMic
        self.enableCam = options.enableCam
        logUnsupportedOptions()
    }

    // Add this method to configure with API key
    internal func configure(apiKey: String, initialMessages: [WebSocketMessages.Outbound.TextInput] = [], generationConfig: Value? = nil) {
        connection.configure(
            apiKey: apiKey,
            initialMessages: initialMessages,
            generationConfig: generationConfig
        )
    }
    
    public func initDevices() async throws {
        if (self.devicesInitialized) {
            // There is nothing to do in this case
            return
        }
        
        self.setState(state: .initializing)
        
        // start managing audio device configuration
        audioManager.startManagingIfNecessary()
        
        // initialize devices state and report initial available & selected devices
        self._selectedMic = self.getSelectedMic()
        self.delegate?.onAvailableMicsUpdated(mics: self.getAllMics());
        self.delegate?.onMicUpdated(mic: self._selectedMic)
        
        // hook up audio input
        hookUpAudioInputStream()
        
        self.setState(state: .initialized)
        self.devicesInitialized = true
    }
    
    public func release() {
        // stop audio input and terminate stream
        audioRecorder.stop()
        audioRecorder.terminateAudioStream()
        
        // stop audio player
        audioPlayer.stop()
        
        // stop managing audio device configuration and reset mic bookkeeping
        audioManager.stopManaging()
        _selectedMic = nil
    }
    
    public func connect(transportParams: TransportConnectionParams?) async throws {
        print("🔍 DEBUG: GeminiLiveWebSocketTransport.connect() called")
        print("🔍 DEBUG: transportParams: \(transportParams as Any)")
        
        self.setState(state: .connecting)
        
        // start audio player
        print("🔍 DEBUG: Starting audio player")
        try audioPlayer.start()
        
        // start audio input if needed
        // this is done before connecting WebSocket to guarantee that by the time we transition to the .connected state isMicEnabled() reflects the truth
        if enableMic {
            print("🔍 DEBUG: Resuming audio recorder (mic enabled)")
            try audioRecorder.resume()
        } else {
            print("🔍 DEBUG: Mic disabled - not starting audio recorder")
        }
        
        // start connecting
        print("🔍 DEBUG: About to call connection.connect()")
        try await connection.connect()
        print("🔍 DEBUG: connection.connect() completed")
        
        // initialize tracks (which are just dummy values)
        updateTracks(
            localAudio: .init(id: UUID().uuidString),
            botAudio: .init(id: UUID().uuidString)
        )
        
        // go to connected state
        // (unless we've already leaped ahead to the ready state - see connectionDidFinishModelSetup())
        if _state == .connecting {
            self.setState(state: .connected)
        }
    }
    
    public func disconnect() async throws {
        // stop websocket connection
        connection.disconnect()
        
        // stop audio input
        // (why not just pause it? to avoid problems in case the user forgets to call release() before instantiating a new voice client)
        audioRecorder.stop()
        
        // stop audio player
        audioPlayer.stop()
        
        // clear tracks (which are just dummy values)
        updateTracks(
            localAudio: nil,
            botAudio: nil
        )
        
        setState(state: .disconnected)
    }
    
    public func getAllMics() -> [MediaDeviceInfo] {
        audioManager.availableDevices.map { $0.toRtvi() }
    }
    
    public func getAllCams() -> [MediaDeviceInfo] {
        logOperationNotSupported(#function)
        return []
    }
    
    public func updateMic(micId: MediaDeviceId) async throws {
        audioManager.preferredAudioDevice = .init(deviceID: micId.id)
        
        // Refresh what we should report as the selected mic
        refreshSelectedMicIfNeeded()
    }
    
    public func updateCam(camId: MediaDeviceId) async throws {
        logOperationNotSupported(#function)
    }
    
    /// What we report as the selected mic.
    public func selectedMic() -> MediaDeviceInfo? {
        _selectedMic
    }
    
    public func selectedCam() -> MediaDeviceInfo? {
        logOperationNotSupported(#function)
        return nil
    }
    
    public func enableMic(enable: Bool) async throws {
        if enable {
            try audioRecorder.resume()
        } else {
            audioRecorder.pause()
        }
    }
    
    public func enableCam(enable: Bool) async throws {
        logOperationNotSupported(#function)
    }
    
    public func isCamEnabled() -> Bool {
        logOperationNotSupported(#function)
        return false
    }
    
    public func isMicEnabled() -> Bool {
        return audioRecorder.isRecording
    }
    
    public func sendMessage(message: RTVIMessageOutbound) throws {
        // Simplified implementation - just log that message sending is not supported
        logOperationNotSupported("\(#function)")
        
        // Send error response to indicate failure
        onMessage?(.init(
            type: RTVIMessageInbound.MessageType.ERROR_RESPONSE,
            data: "Message sending not supported in Gemini WebSocket transport",
            id: message.id
        ))
    }
    
    public func state() -> TransportState {
        self._state
    }
    
    public func setState(state: TransportState) {
        let previousState = self._state
        
        self._state = state
        self.delegate?.onTransportStateChanged(state: self._state)
        
        // Fire delegate methods as needed
        if state != previousState {
            if state == .connected {
                self.delegate?.onConnected()
                // New bot participant id each time we connect
                connectedBotParticipant = Participant(
                    id: ParticipantId(id: UUID().uuidString),
                    name: connectedBotParticipant.name,
                    local: connectedBotParticipant.local
                )
                self.delegate?.onParticipantJoined(participant: connectedBotParticipant)
                self.delegate?.onBotConnected(participant: connectedBotParticipant)
            }
            if state == .disconnected {
                self.delegate?.onParticipantLeft(participant: connectedBotParticipant)
                self.delegate?.onBotDisconnected(participant: connectedBotParticipant)
                self.delegate?.onDisconnected()
            }
        }
    }
    
    public func isConnected() -> Bool {
        return [.connected, .ready].contains(self._state)
    }
    
    public func tracks() -> Tracks? {
        return .init(
            local: .init(
                audio: localAudioTrackID?.toMediaStreamTrack(),
                video: nil, // video not yet supported
                screenAudio: nil,
                screenVideo: nil
            ),
            bot: .init(
                audio: botAudioTrackID?.toMediaStreamTrack(),
                video: nil, // video not yet supported
                screenAudio: nil,
                screenVideo: nil
            )
        )
    }
    
    public func expiry() -> Int? {
        return nil
    }
    
    // MARK: - Private
    
    private var enableMic: Bool
    private var enableCam: Bool
    private var _state: TransportState = .disconnected
    internal let connection: GeminiLiveWebSocketConnection
    private let audioManager = AudioManager()
    private let audioPlayer = AudioPlayer()
    private let audioRecorder = AudioRecorder()
    private var connectedBotParticipant = Participant(
        id: ParticipantId(id: UUID().uuidString),
        name: "Gemini Multimodal Live",
        local: false
    )
    private var devicesInitialized: Bool = false
    private var _selectedMic: MediaDeviceInfo?
    
    // audio tracks aren't directly useful to the user; they're just dummy values for API completeness
    private var localAudioTrackID: MediaTrackId?
    private var botAudioTrackID: MediaTrackId?
    
    // MARK: - End-of-speech detection config
    private let silenceDbThreshold: Float = -40.0
    private let silentFramesForEnd: Int = 6
    private let audioStreamEndCooldownNs: UInt64 = 300_000_000
    private var consecutiveSilentFrames: Int = 0
    private var recentlySentAudioStreamEnd: Bool = false
    
    private func hookUpAudioInputStream() {
        Task {
            for await audio in audioRecorder.streamAudio() {
                do {
                    try await connection.sendUserAudio(audio)
                } catch {
                    Logger.shared.warn("Send user audio failed: \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func logUnsupportedOptions() {
        if enableCam {
            logOperationNotSupported("enableCam option")
        }
        // Note: Removed options validation since PipecatClientOptions has different structure
    }
    
    private func logOperationNotSupported(_ operationName: String) {
        Logger.shared.warn("\(operationName) not supported")
    }
    
    /// Refresh what we should report as the selected mic.
    private func refreshSelectedMicIfNeeded() {
        let newSelectedMic = getSelectedMic()
        if newSelectedMic != _selectedMic {
            _selectedMic = newSelectedMic
            delegate?.onMicUpdated(mic: _selectedMic)
        }
    }
    
    private func adaptToDeviceChange() {
        do {
            try audioPlayer.adaptToDeviceChange()
        } catch {
            Logger.shared.error("Audio player failed to adapt to device change")
        }
        do {
            try audioRecorder.adaptToDeviceChange()
        } catch {
            Logger.shared.error("Audio recorder failed to adapt to device change")
        }
    }
    
    // updates tracks.
    // note that they're not directly useful to the user; they're just dummy values for API completeness.
    private func updateTracks(localAudio: MediaTrackId?, botAudio: MediaTrackId?) {
        if localAudio == localAudioTrackID && botAudio == botAudioTrackID {
            return
        }
        localAudioTrackID = localAudio
        botAudioTrackID = botAudio
        // onTracksUpdated method doesn't exist in current API - remove this call
    }
    
    /// Selected mic is a value derived from the preferredAudioDevice and the set of available devices, so it may change whenever either of those change.
    private func getSelectedMic() -> MediaDeviceInfo? {
        audioManager.availableDevices.first { $0.deviceID == audioManager.preferredAudioDeviceIfAvailable?.deviceID }?.toRtvi()
    }
}

// MARK: - GeminiLiveWebSocketConnection.Delegate

extension GeminiLiveWebSocketTransport: GeminiLiveWebSocketConnectionDelegate {
    func connectionDidFinishModelSetup(_: GeminiLiveWebSocketConnection) {
        // If this happens *before* we've entered the connected state, first pass through that state
        if _state == .connecting {
            self.setState(state: .connected)
        }
        
        // Synthesize (i.e. fake) an RTVI-style "bot ready" response from the server
        // TODO: can we fill in more meaningful BotReadyData someday?
        let botReadyData = BotReadyData(version: "n/a", about: "Gemini Live WebSocket Bot")
        onMessage?(.init(
            type: RTVIMessageInbound.MessageType.BOT_READY,
            data: String(data: try! JSONEncoder().encode(botReadyData), encoding: .utf8),
            id: String(UUID().uuidString.prefix(8))
        ))
    }
    
    func connection(
        _: GeminiLiveWebSocketConnection,
        didReceiveModelAudioBytes audioBytes: Data
    ) {
        audioPlayer.enqueueBytes(audioBytes)
    }
    
    func connectionDidDetectUserInterruption(_: GeminiLiveWebSocketConnection) {
        audioPlayer.clearEnqueuedBytes()
        delegate?.onUserStartedSpeaking()
    }
}

// MARK: - AudioPlayer.Delegate

extension GeminiLiveWebSocketTransport: AudioPlayerDelegate {
    func audioPlayerDidStartPlayback(_ audioPlayer: AudioPlayer) {
        delegate?.onBotStartedSpeaking()
    }
    
    func audioPlayerDidFinishPlayback(_ audioPlayer: AudioPlayer) {
        delegate?.onBotStoppedSpeaking()
    }
    
    func audioPlayer(_ audioPlayer: AudioPlayer, didGetAudioLevel audioLevel: Float) {
        // onRemoteAudioLevel method signature changed - use the correct one
        delegate?.onRemoteAudioLevel(level: audioLevel, participant: connectedBotParticipant)
    }
}

// MARK: - AudioRecorder.Delegate

extension GeminiLiveWebSocketTransport: AudioRecorderDelegate {
    func audioRecorder(_ audioPlayer: AudioRecorder, didGetAudioLevel audioLevel: Float) {
        // Simple silence detection to signal end-of-speech quickly
        let level = audioLevel // dBFS; lower is quieter
        let isSilent = level < silenceDbThreshold
        if isSilent {
            consecutiveSilentFrames += 1
            if !recentlySentAudioStreamEnd && consecutiveSilentFrames >= silentFramesForEnd {
                recentlySentAudioStreamEnd = true
                Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.connection.sendAudioStreamEnd()
                    } catch {
                        Logger.shared.warn("Failed to send audioStreamEnd: \(error.localizedDescription)")
                    }
                    // cooldown before allowing another audioStreamEnd to avoid spamming
                    try? await Task.sleep(nanoseconds: audioStreamEndCooldownNs)
                    self.recentlySentAudioStreamEnd = false
                }
            }
        } else {
            consecutiveSilentFrames = 0
        }
    }
}

// MARK: - AudioManagerDelegate

extension GeminiLiveWebSocketTransport: AudioManagerDelegate {
    func audioManagerDidChangeAvailableDevices(_ audioManager: AudioManager) {
        // Report available mics changed
        delegate?.onAvailableMicsUpdated(mics: getAllMics())
        
        // Refresh what we should report as the selected mic
        refreshSelectedMicIfNeeded()
    }
    
    func audioManagerDidChangeAudioDevice(_ audioManager: AudioManager) {
        adaptToDeviceChange()
    }
}

// MARK: - Extensions

extension MediaTrackId {
    func toMediaStreamTrack() -> MediaStreamTrack? {
        return MediaStreamTrack(id: self, kind: .audio)
    }
}
