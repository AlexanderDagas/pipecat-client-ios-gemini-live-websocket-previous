import Foundation
import PipecatClientIOS

/// An RTVI client. Connects to a Gemini Live WebSocket backend and handles bidirectional audio streaming
@MainActor
public class GeminiLiveWebSocketVoiceClient {
    private let pipecatClient: PipecatClient
    
    public init(options: PipecatClientOptions) {
        self.pipecatClient = PipecatClient(options: options)
    }
    
    public func start() async throws {
        // Delegate to PipecatClient
        // Implementation needed here
    }
    
    public func disconnect() async {
        // Delegate to PipecatClient  
        // Implementation needed here
    }
}
