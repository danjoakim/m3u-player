import Foundation

enum SourceKind: String, CaseIterable {
    case m3u, xtream
}

/// Svar fra Xtream Codes `player_api.php`.
nonisolated struct XtreamAccount {
    let authenticated: Bool
    let status: String?
    let expiry: Date?

    init?(json data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let info = root["user_info"] as? [String: Any] else { return nil }
        let auth = info["auth"]
        authenticated = (auth as? Int) == 1 || (auth as? String) == "1"
        status = info["status"] as? String
        if let text = info["exp_date"] as? String, let seconds = TimeInterval(text) {
            expiry = Date(timeIntervalSince1970: seconds)
        } else if let seconds = info["exp_date"] as? TimeInterval {
            expiry = Date(timeIntervalSince1970: seconds)
        } else {
            expiry = nil
        }
    }
}
