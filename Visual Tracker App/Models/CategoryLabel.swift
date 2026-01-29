import Foundation
import SwiftData

@Model
final class CategoryLabel {
    @Attribute(.unique) var key: String
    var code: String
    var title: String

    init(code: String, title: String) {
        self.key = code
        self.code = code
        self.title = title
    }
}