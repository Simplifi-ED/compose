import Foundation

package enum ComposeSSHDecoder {
    package static func decodeList<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        key: K,
        fieldName: String
    ) throws -> [String]? {
        guard container.contains(key) else { return nil }
        if let value = try? container.decode(String.self, forKey: key) {
            return [value]
        }
        if let value = try? container.decode([String].self, forKey: key) {
            return value
        }
        throw ComposeError.invalidField(fieldName, reason: "expected a string or list of strings")
    }
}
