import Foundation

enum EmojiDetector {
    static func isEmoji(_ value: String) -> Bool {
        guard value.count == 1 else { return false }
        return value.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji
        }
    }

    static func firstEmoji(in value: String) -> String? {
        for character in value {
            if isEmoji(String(character)) {
                return String(character)
            }
        }
        return nil
    }
}
