import Foundation

enum LearningObjectiveCatalog {
    static func defaultObjectives() -> [LearningObjective] {
        var objectives: [LearningObjective] = []
        var sortOrder = 0

        objectives.append(LearningObjective(
            code: "A",
            title: "Able to apply 100% of core LOs for chosen path",
            description: "Quantitative - average of A.1, A.2, A.3",
            isQuantitative: true,
            parentCode: nil,
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "A.1",
            title: "Expose core LOs for all",
            description: "0-100%",
            isQuantitative: true,
            parentCode: "A",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "A.2",
            title: "Understand core LOs for all",
            description: "0-100%",
            isQuantitative: true,
            parentCode: "A",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "A.3",
            title: "Apply domain core LOs for their chosen path",
            description: "0-100%",
            isQuantitative: true,
            parentCode: "A",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "B",
            title: "Able to LUR - Learn Unlearn Relearn",
            description: "Qualitative checkboxes",
            isQuantitative: false,
            parentCode: nil,
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "B.L",
            title: "Have a positive attitude for learning",
            description: "",
            isQuantitative: false,
            parentCode: "B",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "B.U",
            title: "Be okay/comfortable to have existing knowledge challenged",
            description: "",
            isQuantitative: false,
            parentCode: "B",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "B.R",
            title: "Adapt to newly acquired knowledge",
            description: "",
            isQuantitative: false,
            parentCode: "B",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C",
            title: "Able to analyze and create solutions based on data",
            description: "Nested hierarchy",
            isQuantitative: false,
            parentCode: nil,
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.1",
            title: "Data Gathering & Understanding",
            description: "",
            isQuantitative: false,
            parentCode: "C",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.1.1",
            title: "Understand the importance of data",
            description: "",
            isQuantitative: false,
            parentCode: "C.1",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.1.2",
            title: "Understand how to gather & understand data",
            description: "",
            isQuantitative: false,
            parentCode: "C.1",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.1.3",
            title: "Apply gathering & understanding of data",
            description: "",
            isQuantitative: false,
            parentCode: "C.1",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.2",
            title: "Data Synthesis & Analysis",
            description: "",
            isQuantitative: false,
            parentCode: "C",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.2.1",
            title: "Exposure to synthesize & analyze data",
            description: "",
            isQuantitative: false,
            parentCode: "C.2",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.2.2",
            title: "Understand how to synthesize & analyze data",
            description: "",
            isQuantitative: false,
            parentCode: "C.2",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.2.3",
            title: "Apply synthesis & analysis of data",
            description: "",
            isQuantitative: false,
            parentCode: "C.2",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.3",
            title: "Data-Driven Decision Making",
            description: "",
            isQuantitative: false,
            parentCode: "C",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.3.1",
            title: "Understand how to make data-driven decisions",
            description: "",
            isQuantitative: false,
            parentCode: "C.3",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.3.2",
            title: "Apply making data-driven decisions",
            description: "",
            isQuantitative: false,
            parentCode: "C.3",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.4",
            title: "Data-Based Argumentation",
            description: "",
            isQuantitative: false,
            parentCode: "C",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.4.1",
            title: "Understand how to argue/defend/enrich decisions based on data",
            description: "",
            isQuantitative: false,
            parentCode: "C.4",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "C.4.2",
            title: "Apply argumentation/defense/enrichment based on data",
            description: "",
            isQuantitative: false,
            parentCode: "C.4",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "D",
            title: "Able to create positive influence and empower each other",
            description: "Qualitative",
            isQuantitative: false,
            parentCode: nil,
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "D.1",
            title: "Self-Leadership",
            description: "",
            isQuantitative: false,
            parentCode: "D",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "D.2",
            title: "Share Responsibility",
            description: "",
            isQuantitative: false,
            parentCode: "D",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "D.3",
            title: "Inspire Others",
            description: "",
            isQuantitative: false,
            parentCode: "D",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "E",
            title: "Able to identify pathways & requirements toward career aspiration",
            description: "Qualitative",
            isQuantitative: false,
            parentCode: nil,
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "E.1",
            title: "Self-Discovery",
            description: "",
            isQuantitative: false,
            parentCode: "E",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "E.2",
            title: "Knowing Your Options",
            description: "",
            isQuantitative: false,
            parentCode: "E",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "E.3",
            title: "Decide the Area of Exploration",
            description: "",
            isQuantitative: false,
            parentCode: "E",
            sortOrder: sortOrder
        ))
        sortOrder += 1

        objectives.append(LearningObjective(
            code: "E.4",
            title: "Planning Actions in Decided Path",
            description: "",
            isQuantitative: false,
            parentCode: "E",
            sortOrder: sortOrder
        ))

        return objectives
    }
}
