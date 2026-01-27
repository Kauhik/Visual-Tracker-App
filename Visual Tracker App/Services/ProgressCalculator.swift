import Foundation

enum ProgressCalculator {
    static func objectivePercentage(student: Student, objectiveCode: String, allObjectives: [LearningObjective]) -> Int {
        let children = allObjectives.filter { $0.parentCode == objectiveCode }
        if children.isEmpty {
            return student.completionPercentage(for: objectiveCode)
        }

        var total = 0
        for child in children {
            total += objectivePercentage(student: student, objectiveCode: child.code, allObjectives: allObjectives)
        }
        return children.isEmpty ? 0 : total / children.count
    }

    static func studentOverall(student: Student, allObjectives: [LearningObjective]) -> Int {
        let rootCategories = allObjectives
            .filter { $0.parentCode == nil }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard rootCategories.isEmpty == false else { return 0 }

        var total = 0
        for category in rootCategories {
            total += objectivePercentage(student: student, objectiveCode: category.code, allObjectives: allObjectives)
        }
        return total / rootCategories.count
    }

    static func cohortObjectiveAverage(objectiveCode: String, students: [Student], allObjectives: [LearningObjective]) -> Int {
        guard students.isEmpty == false else { return 0 }

        var total = 0
        for student in students {
            total += objectivePercentage(student: student, objectiveCode: objectiveCode, allObjectives: allObjectives)
        }
        return total / students.count
    }

    static func cohortOverall(students: [Student], allObjectives: [LearningObjective]) -> Int {
        guard students.isEmpty == false else { return 0 }

        var total = 0
        for student in students {
            total += studentOverall(student: student, allObjectives: allObjectives)
        }
        return total / students.count
    }
}