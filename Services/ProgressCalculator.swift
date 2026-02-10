import Foundation

enum ProgressCalculator {
    static func objectivePercentage(student: Student, objective: LearningObjective, allObjectives: [LearningObjective]) -> Int {
        let children = allObjectives.filter { $0.isChild(of: objective) && $0.isArchived == false }
        if children.isEmpty {
            return student.progress(for: objective)?.value ?? 0
        }

        var total = 0
        for child in children {
            total += objectivePercentage(student: student, objective: child, allObjectives: allObjectives)
        }
        return children.isEmpty ? 0 : total / children.count
    }

    static func studentOverall(student: Student, allObjectives: [LearningObjective]) -> Int {
        let rootCategories = allObjectives
            .filter { $0.isRootCategory && $0.isArchived == false }
            .sorted { $0.sortOrder < $1.sortOrder }

        guard rootCategories.isEmpty == false else { return 0 }

        var total = 0
        for category in rootCategories {
            total += objectivePercentage(student: student, objective: category, allObjectives: allObjectives)
        }
        return total / rootCategories.count
    }

    static func cohortObjectiveAverage(objective: LearningObjective, students: [Student], allObjectives: [LearningObjective]) -> Int {
        guard students.isEmpty == false else { return 0 }

        var total = 0
        for student in students {
            total += objectivePercentage(student: student, objective: objective, allObjectives: allObjectives)
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

    static func groupOverall(
        group: CohortGroup,
        students: [Student],
        memberships: [StudentGroupMembership],
        allObjectives: [LearningObjective]
    ) -> Int {
        let groupStudents = students.filter { student in
            memberships.contains { membership in
                membership.student?.id == student.id && membership.group?.id == group.id
            }
        }
        guard groupStudents.isEmpty == false else { return 0 }

        var total = 0
        for student in groupStudents {
            total += studentOverall(student: student, allObjectives: allObjectives)
        }
        return total / groupStudents.count
    }
}
