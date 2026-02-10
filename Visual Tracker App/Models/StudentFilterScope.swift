import Foundation

enum StudentFilterScope: Hashable {
    case overall
    case ungrouped
    case group(UUID)
    case domain(UUID)
    case noDomain

    func title(groups: [CohortGroup], domains: [Domain]) -> String {
        switch self {
        case .overall:
            return "Overall"
        case .ungrouped:
            return "Ungrouped"
        case .group(let id):
            return groups.first(where: { $0.id == id })?.name ?? "Group"
        case .domain(let id):
            return domains.first(where: { $0.id == id })?.name ?? "Expertise Check"
        case .noDomain:
            return "No Expertise Check"
        }
    }
}
