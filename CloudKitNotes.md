# CloudKit Notes (Visual Tracker App)

- Container reference: the app uses `CKContainer.default()` (configured in Xcode > Signing & Capabilities > iCloud > CloudKit). The selected container in the target settings is the one used at runtime.
- Main cohort: on launch the data layer looks for a Cohort record with `cohortId == "main"`. If none exists, it creates one with record name `"main"`.
- Reset dev data: use the in‑app toolbar menu → "Reset Data" to delete all cohort-scoped records in the Public database (Groups, Domains, Students, CategoryLabels, Progress, Custom Properties). This is intended for development only.
