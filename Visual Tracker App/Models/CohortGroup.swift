import Foundation
import SwiftData

@Model
final class CohortGroup {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var name: String
    var colorHex: String?

    init(name: String, colorHex: String? = nil) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
    }
}
