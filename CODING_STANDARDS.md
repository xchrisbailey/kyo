# Coding standards

Rules a reviewer applies to a diff. Each one is a judgement call that no build step checks. The coder instructions in `.claude/agents/coder.md` cover how to work; this file covers what the result should look like.

## Domain language

Names, comments, test names, and on-screen text use the terms in `GLOSSARY.md`. A word on a term's _Avoid_ list is a finding when it stands for that term, and fine when it means something else (`calendar` the EventKit type, `history` of a git log).

## Accessibility identifiers

- Write an identifier in kebab-case, leading with what the element is: `schedule-all-day`, `section-header-tasks`.
- Key a repeated element on a stable value such as an enum's raw value or a model id: `section-header-\(section.rawValue)`, `schedule-calendar-\(calendar.id)`. Display text changes with wording and locale.
- A UI test finds an element by its identifier, then asserts its label or value. A query on label text is for a test whose subject is that text.
- `scripts/lint-ui-tests` enforces that rule: it flags a query on a string literal that isn't kebab-case (`app.buttons["Save"]`; `"month-day-\(id)"` passes). Queries that predate it are in `scripts/ui-test-queries.baseline`, so only new ones fail. Mark a deliberate label query with a trailing `// label-query: <reason>`; the reason is required.
- A control that combines its children into one accessibility element carries the label, value, and identifier itself; tests address the control, never the text inside it.

## UserDefaults storage keys

- Declare a store's key as `static let storageKey` on the type that owns the data, the way `TaskListStore` does.
- Name it `kyo.<thing>` in lowerCamelCase and end a new key in a version suffix: `kyo.dailyTasks.v1`.
- A store takes its `UserDefaults` as an initializer argument, defaulting to `.standard`, so a test can pass its own suite.
- Changing a shipped key's value discards what users stored under it. Treat that as a migration.

## Launch variables for UI test state

- A UI test sets up app state through a `KYO_…` launch environment variable. Declare its name once as a `static let …EnvironmentKey` beside the code that reads it, as `CalendarServiceSelection` and `CollapsedSectionsSelection` do.
- One selection type per seam reads the variable and returns the real or the test dependency. Views ask the selection type and stay unaware of the variable.
- A launch with `KYO_IN_MEMORY_STORE` set starts from clean state and writes nothing to the device's real store or standard defaults.
- A test that relaunches to check persistence names its own suite or store, so each launch of that test sees the same state and no other test does.

## Stores in a view's initializer

- A store whose initializer has side effects (registering a handler with a transport, publishing a snapshot, starting observation) is built at most once for the life of the view: inside the autoclosure of `StateObject(wrappedValue:)`, or as a local `lazy var` when a second state object needs the same instance, as `TodayView` does for the stores Month reads.
- A plain `let store = Store(...)` in a view's `init` is a finding. SwiftUI may run that initializer again, and the extra store would take over from the live one and then be discarded.
