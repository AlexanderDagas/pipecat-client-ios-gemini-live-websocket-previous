import Foundation
import PipecatClientIOS

@MainActor
public class GeminiLiveWebSocketVoiceClient {
    private let pipecatClient: PipecatClient
    private let transport: GeminiLiveWebSocketTransport
    
    internal init(apiKey: String, initialMessages: [WebSocketMessages.Outbound.TextInput] = [], generationConfig: Value? = nil) {
        // Create transport
        self.transport = GeminiLiveWebSocketTransport()
        
        // Configure transport with API key
        self.transport.configure(
            apiKey: apiKey,
            initialMessages: initialMessages,
            generationConfig: generationConfig
        )
        
        // Create PipecatClient with transport
        self.pipecatClient = PipecatClient(options: PipecatClientOptions(
            transport: transport,
            enableMic: true,
            enableCam: false
        ))
    }
    
    // Public convenience initializer
    public convenience init(apiKey: String) {
        self.init(apiKey: apiKey, initialMessages: [], generationConfig: nil)
    }
    
    public func start() async throws {
        print("🔍 DEBUG: GeminiLiveWebSocketVoiceClient.start() called")
        
        print("🔍 DEBUG: About to call pipecatClient.initDevices()")
        try await pipecatClient.initDevices()
        print("🔍 DEBUG: pipecatClient.initDevices() completed")
        
        // Connect directly through the transport without using startBot
        // The transport will handle the WebSocket connection to Gemini Live API
        print("🔍 DEBUG: About to call transport.connect()")
        try await transport.connect(transportParams: nil)
        print("🔍 DEBUG: transport.connect() completed")
    }
    
    public func disconnect() async {
        try? await transport.disconnect()
    }
    
    public var delegate: PipecatClientDelegate? {
        get { transport.delegate }
        set { transport.delegate = newValue }
    }
    
    // Public method to configure system instruction and generation config
    public func configure(systemInstruction: String) {
        print("🔍 DEBUG: Configuring GeminiLiveWebSocketVoiceClient with system instruction")
        print("🔍 DEBUG: System instruction length: \(systemInstruction.count)")
        
        let generationConfig = Value.object([
            "systemInstruction": .string(systemInstruction),
            "responseModalities": .array([.string("AUDIO")]),
            "responseMimeType": .string("application/json"),
            "mediaResolution": .string("MEDIA_RESOLUTION_MEDIUM"),
            "speechConfig": .object([
                "voiceConfig": .object([
                    "prebuiltVoiceConfig": .object([
                        "voiceName": .string("Gacrux")
                    ])
                ])
            ])
        ])
        
        // Configure the transport with the system instruction
        transport.configure(
            apiKey: transport.connection.options?.apiKey ?? "",
            initialMessages: [],
            generationConfig: generationConfig
        )
        
        print("✅ GeminiLiveWebSocketVoiceClient configured with system instruction")
    }
}
