import Foundation

enum GoogleConfiguration {
    static func value(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.contains("$("), !value.contains("YOUR_") else { return nil }
        return value
    }
    static var clientID: String? { value("GIDClientID") }
}
