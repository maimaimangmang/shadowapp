import Foundation

public enum ProfileName {
    public static func validate(_ raw: String, profiles: [Profile], excluding id: UUID? = nil) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 40, value.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw LauncherError("名称需要 1–40 个字符，不能包含换行或控制字符。", "Use 1–40 characters without line breaks or control characters.")
        }
        guard !profiles.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(value) == .orderedSame }) else {
            throw LauncherError("这个空间名称已存在，请换一个名称。", "A profile with this name already exists. Choose a different name.")
        }
        return value
    }
}
