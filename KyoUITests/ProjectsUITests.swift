import XCTest

@MainActor
final class ProjectsUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testBottomProjectCaptureKeepsSelectionThroughSchedulingCancelAndDefaultsToday() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        tapRevealed(app.buttons["section-link-projects"], in: app)
        app.buttons["project-new"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Build Kyo")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        let projectID = String(project.identifier.dropFirst("project-open-".count))
        app.buttons["projects-done"].tap()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.typeText("Build widgets")
        let picker = app.buttons["new-task-project-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["new-task-project-option-\(projectID)"].tap()
        XCTAssertEqual(picker.value as? String, "Build Kyo")
        app.buttons["new-task-schedule"].tap()
        app.buttons["task-scheduling-cancel"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.value as? String, "Build widgets")
        XCTAssertEqual(picker.value as? String, "Build Kyo")
        entry.tap()
        entry.typeText("\n")
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-edit-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let id = String(row.identifier.dropFirst("task-edit-".count))
        tapRevealed(app.buttons["task-checkbox-\(id)"], in: app)
        row.press(forDuration: 1)
        let remove = app.buttons["task-remove-project-\(id)"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(app.buttons["task-checkbox-\(id)"].waitForExistence(timeout: 5))
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "No project")
    }

    func testBottomFutureProjectCaptureCanSwitchAndRemoveAssignmentInLater() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        tapRevealed(app.buttons["section-link-projects"], in: app)
        var projectIDs: [String] = []
        for title in ["Kyo", "House"] {
            app.buttons["project-new"].tap()
            let name = app.textFields["project-name-editor"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(title)
            app.buttons["project-name-save"].tap()
            let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).element(boundBy: projectIDs.count)
            XCTAssertTrue(project.waitForExistence(timeout: 5))
            projectIDs.append(String(project.identifier.dropFirst("project-open-".count)))
        }
        app.buttons["projects-done"].tap()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.typeText("Plan widgets")
        app.buttons["new-task-project-picker"].tap()
        app.buttons["new-task-project-option-\(projectIDs[0])"].tap()
        app.buttons["new-task-schedule"].tap()
        app.buttons["task-scheduling-one-week"].tap()
        app.buttons["task-scheduling-confirm"].tap()
        tapRevealed(app.buttons["section-link-tasks"], in: app)
        let task = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "later-task-")).matching(NSPredicate(format: "label == %@", "Plan widgets")).firstMatch
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        let id = String(task.identifier.dropFirst("later-task-".count))
        let planned = app.staticTexts["later-task-planned-day-\(id)"].label
        XCTAssertEqual(app.staticTexts["later-task-project-\(id)"].label, "Kyo")
        app.buttons["task-move-project-\(id)"].tap()
        app.buttons["task-project-option-\(projectIDs[1])"].tap()
        XCTAssertEqual(app.staticTexts["later-task-project-\(id)"].label, "House")
        XCTAssertEqual(app.staticTexts["later-task-planned-day-\(id)"].label, planned)
        app.buttons["task-remove-project-\(id)"].tap()
        XCTAssertFalse(app.staticTexts["later-task-project-\(id)"].exists)
        XCTAssertEqual(app.staticTexts["later-task-planned-day-\(id)"].label, planned)
        XCTAssertEqual(task.label, "Plan widgets")
    }

    func testProjectSchedulingCancellationLaterMonthAndReturn() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        tapRevealed(app.buttons["section-link-projects"], in: app)
        app.buttons["project-new"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Build Kyo")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.tap()
        app.buttons["project-add-task"].tap()
        let task = app.textFields["project-task-editor"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        task.typeText("Plan widgets")
        app.buttons["project-task-save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-edit-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let id = String(row.identifier.dropFirst("task-edit-".count))
        row.press(forDuration: 1)
        let schedule = app.buttons["task-do-later-\(id)"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        app.buttons["task-scheduling-one-week"].tap()
        app.buttons["task-scheduling-cancel"].tap()
        XCTAssertTrue(app.buttons["task-do-today-\(id)"].waitForExistence(timeout: 5))
        row.press(forDuration: 1)
        schedule.tap()
        app.buttons["task-scheduling-one-week"].tap()
        XCTAssertTrue(app.staticTexts["task-planned-day-preview"].exists)
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["task-do-today-\(id)"].exists)
        app.buttons["projects-done"].tap()
        tapRevealed(app.buttons["section-link-tasks"], in: app)
        XCTAssertTrue(app.staticTexts["later-task-\(id)"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["later-task-\(id)"].label, "Plan widgets")
        XCTAssertEqual(app.staticTexts["later-task-project-\(id)"].label, "Build Kyo")
        capture("project-task-unified-later", in: app)
        app.buttons["later-done"].tap()
        app.buttons["main-view-month"].tap()
        let calendar = Calendar.current
        let date = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: Date.now))
        if !calendar.isDate(date, equalTo: Date.now, toGranularity: .month) { app.buttons["month-next"].tap() }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let cell = app.buttons["month-day-\(formatter.string(from: date))"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertTrue(cell.label.contains("1 task planned"))
        cell.tap()
        let summary = app.descendants(matching: .any)["month-summary-row-task-\(id)"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertEqual(summary.label, "Plan widgets, Build Kyo")
        XCTAssertEqual(summary.value as? String, "Planned")
        XCTAssertNotEqual(summary.elementType, .button)
        capture("project-task-read-only-month", in: app)
        app.buttons["main-view-today"].tap()
        tapRevealed(app.buttons["section-link-tasks"], in: app)
        let returned = app.buttons["later-task-return-to-project-\(id)"]
        XCTAssertTrue(returned.waitForExistence(timeout: 5))
        returned.tap()
        XCTAssertTrue(app.staticTexts["later-task-\(id)"].waitForNonExistence(timeout: 5))
        app.buttons["later-done"].tap()
        tapRevealed(app.buttons["section-link-projects"], in: app)
        project.tap()
        XCTAssertTrue(app.buttons["task-do-today-\(id)"].waitForExistence(timeout: 5))
    }

    func testProjectCaptureDefaultsUnscheduledAndOffersExplicitTodayAndPlannedDay() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        tapRevealed(app.buttons["section-link-projects"], in: app)
        app.buttons["project-new"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Kyo")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        project.tap()
        app.buttons["project-add-task"].tap()
        let task = app.textFields["project-task-editor"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["project-task-availability"].label, "Unscheduled")
        task.tap()
        task.typeText("Chosen during capture")
        app.buttons["project-task-today"].tap()
        app.buttons["project-task-save"].tap()
        let checkbox = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-checkbox-")).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        XCTAssertEqual(checkbox.label, "Chosen during capture")
        let chosenCheckboxID = checkbox.identifier
        app.buttons["project-add-task"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["project-task-availability"].label, "Unscheduled")
        task.tap()
        task.typeText("Planned during capture")
        app.buttons["project-task-schedule"].tap()
        app.buttons["task-scheduling-one-week"].tap()
        app.buttons["task-scheduling-confirm"].tap()
        capture("project-task-planned-capture", in: app)
        app.buttons["project-task-save"].tap()
        let day = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-task-planned-day-")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        let id = String(day.identifier.dropFirst("project-task-planned-day-".count))
        XCTAssertEqual(app.buttons["task-edit-\(id)"].label, "Edit task: Planned during capture")
        XCTAssertFalse(app.buttons["task-do-today-\(id)"].exists)
        let detail = app.collectionViews.containing(.button, identifier: "project-add-task").firstMatch
        let checkboxes = detail.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-checkbox-"))
        XCTAssertEqual(checkboxes.count, 2)
        XCTAssertEqual(Set(checkboxes.allElementsBoundByIndex.map(\.identifier)),
                       Set([chosenCheckboxID, "task-checkbox-\(id)"]))
        capture("project-task-capture-details", in: app)
    }

    func testChoosingProjectWorkShowsGroupNavigationCaptureCompletionAndCollapse() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        tapRevealed(app.buttons["section-link-projects"], in: app)
        app.buttons["project-new"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Build Kyo and a daily planner for every device")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        let projectID = String(project.identifier.dropFirst("project-open-".count))
        project.tap()
        app.buttons["project-add-task"].tap()
        let task = app.textFields["project-task-editor"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        task.typeText("Widgets")
        app.buttons["project-task-save"].tap()
        let choose = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-do-today-")).firstMatch
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        choose.tap()
        app.buttons["projects-done"].tap()
        capture("project-section-long-name", in: app)
        let group = app.buttons["project-group-collapse-\(projectID)"]
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertEqual(group.value as? String, "expanded")
        XCTAssertEqual(app.staticTexts["project-group-summary-\(projectID)"].label, "0 of 1 done")
        tapRevealed(group, in: app)
        XCTAssertEqual(group.value as? String, "collapsed")
        tapRevealed(app.buttons["project-group-open-\(projectID)"], in: app)
        let completed = app.buttons["project-completed-collapse-\(projectID)"]
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertEqual(completed.value as? String, "expanded")
        completed.tap()
        app.buttons["projects-done"].tap()
        XCTAssertEqual(group.value as? String, "collapsed")
        tapRevealed(group, in: app)
        tapRevealed(app.buttons["project-group-add-\(projectID)"], in: app)
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.tap()
        task.typeText("Sync")
        app.buttons["project-task-save"].tap()
        XCTAssertEqual(app.staticTexts["project-group-summary-\(projectID)"].label, "0 of 2 done")
        let checkbox = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-checkbox-")).firstMatch
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        tapRevealed(checkbox, in: app)
        XCTAssertEqual(app.staticTexts["project-group-summary-\(projectID)"].label, "1 of 2 done")
        XCTAssertEqual(app.descendants(matching: .any)["task-count-summary"].value as? String, "1 / 2 tasks done")
        capture("project-today-group-long-name", in: app)
    }

    func testProjectNavigationCaptureRenameAndIndependentCollapsedHeaderLink() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        selectTheme("neko", palette: "Light", in: app)
        let header = app.buttons["section-header-projects"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        XCTAssertEqual(header.value as? String, "expanded")
        XCTAssertEqual(app.staticTexts["projects-empty"].label, "No project tasks for today")
        header.tap()
        XCTAssertEqual(header.value as? String, "collapsed")
        app.buttons["section-link-projects"].tap()
        app.buttons["project-new"].tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        capture("projects-neko-light-new-project", in: app)
        name.tap()
        name.typeText("Kyo")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        XCTAssertEqual(project.label, "Kyo")
        capture("all-projects-neko-light", in: app)
        project.tap()
        app.buttons["project-add-task"].tap()
        let task = app.textFields["project-task-editor"]
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        capture("project-task-form-neko-light", in: app)
        task.tap()
        task.typeText("Explore widgets")
        app.buttons["project-task-save"].tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-edit-")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Edit task: Explore widgets")
        capture("project-detail-neko-light", in: app)
        let id = String(row.identifier.dropFirst("task-edit-".count))
        row.tap()
        let editor = app.textFields["task-editor-\(id)"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 15) + "Build widgets\n")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.label, "Edit task: Build widgets")
        row.swipeLeft()
        app.buttons["task-delete-\(id)"].tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        app.buttons["project-rename"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "Build Kyo")
        app.buttons["project-name-save"].tap()
        app.buttons["projects-done"].tap()
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertEqual(header.value as? String, "collapsed")
        XCTAssertEqual(app.buttons["section-header-tasks"].label, "Tasks, For today")
    }

    func testEmptyTodayNewProjectOpensCaptureDirectly() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        selectTheme("techo", palette: "Dark", in: app)
        let create = app.buttons["projects-new"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let name = app.textFields["project-name-editor"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        capture("projects-techo-dark-new-project", in: app)
        name.tap()
        name.typeText("House")
        app.buttons["project-name-save"].tap()
        let project = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-open-")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 5))
        XCTAssertEqual(project.label, "House")
        capture("all-projects-techo-dark", in: app)
        project.tap()
        XCTAssertTrue(app.buttons["project-add-task"].waitForExistence(timeout: 5))
        capture("project-detail-techo-dark", in: app)
    }
    private func tapRevealed(_ control: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<16 {
            let bottom = app.buttons["add-item"].frame.minY - 12
            if control.isHittable && control.frame.maxY < bottom && control.frame.minY >= scroll.frame.minY {
                control.tap()
                return
            }
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: control.frame.maxY >= bottom ? 0.4 : 0.8))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Control remained outside the visible Today scroll area: \(control.identifier), frame \(control.frame), scroll \(scroll.frame)")
    }

    private func selectTheme(_ id: String, palette: String, in app: XCUIApplication) {
        app.buttons["settings-button"].tap()
        let theme = app.buttons["theme-card-\(id)"]
        XCTAssertTrue(theme.waitForExistence(timeout: 5))
        theme.tap()
        let picker = app.segmentedControls["palette-picker"]
        picker.buttons[palette].tap() // label-query: native palette segments have no identifiers
        app.buttons["settings-done"].tap()
    }

    private func capture(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
