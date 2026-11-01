import Foundation

/// One user-defined section of the Titles list. Its position in `Preferences.matchingGroups` is both the
/// section's draw order and its priority when a window matches several rules.
struct MatchingGroupRule: Codable, Equatable {
    var id: UUID
    var name: String
    /// `NSPredicate.predicateFormat` over the keys of `MatchingGroupFacts`.
    var predicateFormat: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, predicateFormat: String, isEnabled: Bool) {
        self.id = id
        self.name = name
        self.predicateFormat = predicateFormat
        self.isEnabled = isEnabled
    }

    /// Permissive so data written before a field existed still decodes: `getThenConvertOrReset` deletes the
    /// whole key on a decode failure. `predicateFormat` is the only field a rule is meaningless without.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        predicateFormat = try c.decode(String.self, forKey: .predicateFormat)
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? true
    }

    /// The JSON array stored under `matchingGroups`, minus any entry that fails to decode. nil only when the
    /// value isn't an array at all.
    static func decodeList(_ json: String) -> [MatchingGroupRule]? {
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([LenientDecodable<MatchingGroupRule>].self, from: data) else { return nil }
        return list.compactMap { $0.value }
    }
}

/// Decodes to `nil` instead of failing, so one corrupt element doesn't fail the array around it.
struct LenientDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

extension Array {
    /// Moves the element at `from` so it lands before what was at `to` (an `NSTableView` `.above` drop
    /// index, counted before the removal). `to == count` moves it to the end.
    func moved(from: Int, to: Int) -> [Element] {
        guard indices.contains(from), to >= 0, to <= count else { return self }
        var result = self
        let element = result.remove(at: from)
        result.insert(element, at: to > from ? to - 1 : to)
        return result
    }
}
