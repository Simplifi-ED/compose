import Foundation

enum ComposeSerializeKeys {
    static func exportCondition(_ condition: DependsOnCondition) -> String {
        switch condition {
        case .orderingOnly, .serviceStarted:
            return DependsOnCondition.serviceStarted.rawValue
        case .serviceHealthy:
            return DependsOnCondition.serviceHealthy.rawValue
        case .serviceCompletedSuccessfully:
            return DependsOnCondition.serviceCompletedSuccessfully.rawValue
        }
    }
}

struct ComposeSerializeCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        return nil
    }
}
