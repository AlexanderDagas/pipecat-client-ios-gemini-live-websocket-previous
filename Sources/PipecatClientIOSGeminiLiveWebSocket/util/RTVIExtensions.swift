import Foundation
import PipecatClientIOS

// Remove all RTVIClientOptions references since they don't exist in 1.0.1
// This file can be simplified or removed entirely

extension PipecatClientOptions {
    var webSocketConnectionOptions: GeminiLiveWebSocketConnection.Options? {
        // Since PipecatClientOptions doesn't contain API key,
        // we'll handle this in the transport initialization
        return nil
    }
}

// Helper extensions for configuration
extension [String: Any] {
    var llmConfig: LLMConfig? {
        // Simplified - we'll handle configuration in the transport
        return nil
    }
}

struct LLMConfig {
    let options: [ConfigOption]
}

struct ConfigOption {
    let name: String
}
