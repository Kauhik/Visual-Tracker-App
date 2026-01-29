import Foundation
import SwiftData

@Model
final class StudentCustomProperty {
    @Attribute(.unique) var id: UUID
    var key: String
    var value: String
    var sortOrder: Int

    var student: Student?

    init(key: String, value: String, sortOrder: Int = 0) {
        self.id = UUID()
        self.key = key
        self.value = value
        self.sortOrder = sortOrder
    }
}