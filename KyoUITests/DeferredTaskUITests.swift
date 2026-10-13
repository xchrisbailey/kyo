import XCTest

@MainActor
final class DeferredTaskUITests: XCTestCase {
    func testCreatingAPlannedTaskConfirmsIntoLaterWithoutChangingTaskText() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText("Call Friday")
        let schedule = app.buttons["new-task-schedule"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        schedule.tap()
        let preview = app.staticTexts["task-planned-day-preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let future = Calendar.current.date(byAdding: .day, value: 7, to: Date.now)!
        let formatter = DateFormatter()
        let wheels = app.datePickers["task-planned-day-picker"].pickerWheels
        XCTAssertEqual(wheels.count, 3)
        formatter.dateFormat = "MMMM"
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: formatter.string(from: future))
        formatter.dateFormat = "d"
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: formatter.string(from: future))
        formatter.dateFormat = "yyyy"
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: formatter.string(from: future))
        formatter.dateFormat = nil
        formatter.dateStyle = .full
        XCTAssertEqual(preview.label, formatter.string(from: future))
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Call Friday"].exists) // label-query: future task text must be absent from Today
        app.buttons["section-header-tasks"].tap()
        XCTAssertEqual(app.buttons["section-header-tasks"].label, "Tasks, No tasks")
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["Call Friday"].waitForExistence(timeout: 5)) // label-query: task text is preserved separately from scheduling
    }

    func testCancelingDateSelectionLeavesAnUnsavedDraftThatCanBeAbandoned() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["new-task-schedule"].isEnabled)
        entry.typeText("Keep Friday in the text")
        app.buttons["new-task-schedule"].tap()
        XCTAssertTrue(app.staticTexts["task-planned-day-preview"].waitForExistence(timeout: 5))
        app.buttons["task-scheduling-cancel"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        XCTAssertEqual(entry.value as? String, "Keep Friday in the text")
        XCTAssertFalse(app.buttons["Keep Friday in the text"].exists) // label-query: canceled date selection must not create a task
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["later-empty"].waitForExistence(timeout: 5))
        app.buttons["later-done"].tap()
        let cancel = app.buttons["new-task-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
        app.buttons["section-header-tasks"].tap()
        XCTAssertEqual(app.buttons["section-header-tasks"].label, "Tasks, No tasks")
    }

    func testBlankEntryCreatesNothingAndTodayConfirmationPreservesPlainTextEntry() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText(" \n")
        XCTAssertTrue(entry.exists)
        XCTAssertEqual(entry.value as? String, " ")
        app.buttons["new-task-cancel"].tap()
        XCTAssertTrue(entry.waitForNonExistence(timeout: 5))
        let summary = app.descendants(matching: .any)["task-count-summary"]
        XCTAssertEqual(summary.value as? String, "0 / 0 tasks done")

        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.typeText("Friday at 3")
        app.buttons["new-task-schedule"].tap()
        XCTAssertTrue(app.staticTexts["task-planned-day-preview"].waitForExistence(timeout: 5))
        app.buttons["task-scheduling-today"].tap()
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(app.buttons["Friday at 3"].waitForExistence(timeout: 5)) // label-query: selecting Today keeps the full task text
        XCTAssertEqual(summary.value as? String, "0 / 1 tasks done")

        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.typeText("October 16\n")
        XCTAssertTrue(app.buttons["October 16"].waitForExistence(timeout: 5)) // label-query: text-only entry never extracts a date
        XCTAssertEqual(summary.value as? String, "0 / 2 tasks done")
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["later-empty"].waitForExistence(timeout: 5))
    }

    func testUnavailableInterpretationKeepsTaskTextSeparateAndManualChoicesUsable() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText("Keep Friday in task text\n")
        let task = app.buttons["Keep Friday in task text"] // label-query: task text must stay separate from scheduling input
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.press(forDuration: 1)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-do-later-")).firstMatch.tap()
        // Scroll beside the date wheels so the gesture moves the Form, rather than a wheel.
        let form = app.collectionViews.firstMatch
        form.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.85))
            .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.2)))
        let unavailable = app.staticTexts["task-scheduling-unavailable"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        let description = app.textFields["task-scheduling-description"]
        description.tap()
        description.typeText("one month out")
        XCTAssertFalse(app.buttons["task-scheduling-interpret"].isEnabled)
        XCTAssertFalse(app.buttons["task-scheduling-confirm"].isEnabled)
        app.swipeDown()
        chooseToday(in: app)
        XCTAssertTrue(app.buttons["task-scheduling-confirm"].isEnabled)
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertEqual(task.value as? String, "Not completed")
    }

    func testQuickChoicesPreviewFullDatesAndOnlyConfirmMovesTaskToLater() throws {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText("Quick choices task\n")
        let task = app.buttons["Quick choices task"] // label-query: task text is the subject of the flow
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.press(forDuration: 1)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-do-later-")).firstMatch.tap()
        let weekday = app.buttons["task-scheduling-weekday"]
        XCTAssertTrue(weekday.waitForExistence(timeout: 5))
        XCTAssertEqual(weekday.label, "Weekday")
        weekday.tap()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let day = calendar.component(.weekday, from: today)
        let weekdayChoice = app.buttons["task-scheduling-weekday-\(day)"]
        XCTAssertTrue(weekdayChoice.waitForExistence(timeout: 5))
        XCTAssertEqual(weekdayChoice.label, calendar.weekdaySymbols[day - 1])
        weekdayChoice.tap()
        let preview = app.staticTexts["task-planned-day-preview"]
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateStyle = .full
        XCTAssertEqual(preview.label, formatter.string(from: today))
        let week = app.buttons["task-scheduling-one-week"]
        XCTAssertEqual(week.label, "One week out")
        week.tap()
        let nextWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: 7, to: today))
        XCTAssertEqual(preview.label, formatter.string(from: nextWeek))
        let month = app.buttons["task-scheduling-one-month"]
        XCTAssertEqual(month.label, "One month out")
        month.tap()
        let nextMonth = try XCTUnwrap(calendar.date(byAdding: .month, value: 1, to: today))
        XCTAssertEqual(preview.label, formatter.string(from: nextMonth))
        app.buttons["task-scheduling-cancel"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.press(forDuration: 1)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-do-later-")).firstMatch.tap()
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        XCTAssertEqual(preview.label, formatter.string(from: nextWeek))
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["Quick choices task"].waitForExistence(timeout: 5)) // label-query: saved task text remains intact
    }

    func testLaterEditsTextWithoutChangingItsPlannedDayAndCanCancelAnEdit() {
        let app = XCUIApplication()
        let plannedDay = openLaterWithDeferredTask(app, text: "Original task")
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "later-task-edit-")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        guard edit.exists else { return }
        edit.tap()
        let entry = app.textFields["later-task-editor"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        entry.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Original task".count) + "Changed task")
        app.buttons["later-edit-cancel"].tap()
        XCTAssertTrue(app.staticTexts["Original task"].exists) // label-query: cancellation preserves saved text
        edit.tap()
        entry.tap()
        entry.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Original task".count) + "Changed task")
        app.buttons["later-edit-save"].tap()
        XCTAssertTrue(app.staticTexts["Changed task"].waitForExistence(timeout: 5)) // label-query: saved edit is the subject
        let day = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "later-task-planned-day-")).firstMatch
        XCTAssertEqual(day.label, plannedDay)
        app.buttons["later-done"].tap()
        XCTAssertFalse(app.buttons["Changed task"].exists) // label-query: edited future task stays off Today
    }

    func testLaterReschedulingPreviewsFullDateAndOnlyConfirmationChangesTheTask() {
        let app = XCUIApplication()
        let originalDay = openLaterWithDeferredTask(app, text: "Reschedule task")
        let reschedule = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "later-task-reschedule-")).firstMatch
        XCTAssertTrue(reschedule.waitForExistence(timeout: 5))
        guard reschedule.exists else { return }
        reschedule.tap()
        let nextDay = Calendar.current.date(byAdding: .day, value: 14, to: Date.now)!
        chooseDate(nextDay, in: app)
        let preview = app.staticTexts["task-planned-day-preview"]
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        XCTAssertEqual(preview.label, formatter.string(from: nextDay))
        app.buttons["task-scheduling-cancel"].tap()
        let savedDay = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "later-task-planned-day-")).firstMatch
        XCTAssertEqual(savedDay.label, originalDay)
        reschedule.tap()
        chooseDate(nextDay, in: app)
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertEqual(savedDay.label, formatter.string(from: nextDay))
        reschedule.tap()
        chooseToday(in: app)
        XCTAssertEqual(preview.label, formatter.string(from: Date.now))
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(app.staticTexts["later-empty"].waitForExistence(timeout: 5))
        app.buttons["later-done"].tap()
        XCTAssertTrue(app.buttons["Reschedule task"].waitForExistence(timeout: 5)) // label-query: choosing Today makes this task available
    }

    func testLaterDeletionRemovesTaskWithoutMakingItAvailableOnToday() {
        let app = XCUIApplication()
        openLaterWithDeferredTask(app, text: "Abandoned task")
        let delete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "later-task-delete-")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        guard delete.exists else { return }
        delete.tap()
        XCTAssertTrue(app.staticTexts["later-empty"].waitForExistence(timeout: 5))
        app.buttons["later-done"].tap()
        XCTAssertFalse(app.buttons["Abandoned task"].exists) // label-query: deleted task must not appear on Today
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["later-empty"].waitForExistence(timeout: 5))
    }

    private func chooseToday(in app: XCUIApplication) {
        let today = app.buttons["task-scheduling-today"]
        if !today.exists {
            // Compact sheets may keep Today below the visible Form cells. Avoid the date wheels.
            let form = app.collectionViews.firstMatch
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.85))
                .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.2)))
        }
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
    }

    @discardableResult
    private func openLaterWithDeferredTask(_ app: XCUIApplication, text: String) -> String {
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText(text + "\n")
        let task = app.buttons[text]
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.press(forDuration: 1)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-do-later-")).firstMatch.tap()
        let future = Calendar.current.date(byAdding: .day, value: 7, to: Date.now)!
        chooseDate(future, in: app)
        let preview = app.staticTexts["task-planned-day-preview"].label
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5))
        return preview
    }

    private func chooseDate(_ date: Date, in app: XCUIApplication) {
        let wheels = app.datePickers["task-planned-day-picker"].pickerWheels
        XCTAssertEqual(wheels.count, 3)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy"
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: formatter.string(from: date))
        formatter.dateFormat = "MMMM"
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: formatter.string(from: date))
        formatter.dateFormat = "d"
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: formatter.string(from: date))
    }

    func testDoLaterCancellationAndConfirmedDateMoveTaskToLaterAndBack() {
        let app = XCUIApplication()
        app.launchEnvironment["KYO_IN_MEMORY_STORE"] = "1"
        app.launch()
        app.buttons["add-item"].tap()
        app.buttons["add-item-task"].tap()
        let entry = app.textFields["new-task"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.typeText("Deferred task\n")
        let task = app.buttons["Deferred task"] // label-query: task text is the subject of the flow
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        task.press(forDuration: 1)
        let laterAction = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-do-later-")).firstMatch
        XCTAssertTrue(laterAction.waitForExistence(timeout: 5))
        laterAction.tap()
        XCTAssertTrue(app.staticTexts["task-planned-day-preview"].waitForExistence(timeout: 5))
        app.buttons["task-scheduling-cancel"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        task.press(forDuration: 1)
        laterAction.tap()
        let future = Calendar.current.date(byAdding: .day, value: 7, to: Date.now)!
        let formatter = DateFormatter()
        let picker = app.datePickers["task-planned-day-picker"]
        let wheels = picker.pickerWheels
        XCTAssertEqual(wheels.count, 3)
        formatter.dateFormat = "MMMM"
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: formatter.string(from: future))
        formatter.dateFormat = "d"
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: formatter.string(from: future))
        formatter.dateFormat = "yyyy"
        wheels.element(boundBy: 2).adjust(toPickerWheelValue: formatter.string(from: future))
        app.buttons["task-scheduling-confirm"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))
        app.buttons["section-link-tasks"].tap()
        XCTAssertTrue(app.staticTexts["Deferred task"].waitForExistence(timeout: 5)) // label-query: saved task text remains intact
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "task-bring-to-today-")).firstMatch.tap()
        app.buttons["later-done"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        XCTAssertEqual(task.value as? String, "Not completed")
    }
}
