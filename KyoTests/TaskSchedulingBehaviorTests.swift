import SwiftData
import XCTest

@MainActor
final class TaskSchedulingBehaviorTests: XCTestCase {
    func testDescriptionPreviewsCalendarIntentAndKeepsTaskTextUntilExplicitConfirmation() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16)))
        let model = FakeOnDeviceLanguageModel()
        model.schedulingAnswer = .interpretation(.intent(.weekday(6)))
        let list = TaskListStore(modelContainer: try KyoModelContainer.make(inMemory: true), now: { today }, calendar: calendar)
        let task = try XCTUnwrap(list.addTask(text: "Call Friday about next month"))
        let workflow = TaskSchedulingWorkflow(now: { today }, calendar: calendar, languageModel: model)
        workflow.schedulingDescription = "Friday"
        await workflow.interpretDescription()
        XCTAssertEqual(workflow.proposedDate, friday)
        XCTAssertEqual(list.tasks, [task])
        XCTAssertTrue(list.laterTasks.isEmpty)
        XCTAssertEqual(model.receivedSchedulingDescriptions, ["Friday"])
        XCTAssertTrue(workflow.confirm { list.deferTask(id: task.id, to: $0) != nil })
        XCTAssertEqual(list.laterTasks.first?.text, task.text)
        XCTAssertEqual(list.laterTasks.first?.plannedOn, TaskPlannedDay(era: 1, year: 2026, month: 10, day: 16))
    }
    func testLanguageIntentUsesAgreedCalendarRulesInsteadOfGeneratedDateArithmetic() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2028, month: 1, day: 31)))
        let model = FakeOnDeviceLanguageModel()
        let workflow = TaskSchedulingWorkflow(now: { today }, calendar: calendar, languageModel: model)
        for (description, intent, month, day) in [
            ("Monday", TaskSchedulingIntent.weekday(2), 1, 31),
            ("next Friday", .nextWeekday(6), 2, 11),
            ("one week out", .weeks(1), 2, 7),
            ("one month out", .months(1), 2, 29),
            ("February 29, 2028", .date(year: 2028, month: 2, day: 29), 2, 29)
        ] {
            model.schedulingAnswer = .interpretation(.intent(intent))
            workflow.schedulingDescription = description
            XCTAssertFalse(workflow.confirm { _ in XCTFail("Uninterpreted text must not save"); return true })
            await workflow.interpretDescription()
            XCTAssertEqual(workflow.proposedDate, calendar.date(from: DateComponents(year: 2028, month: month, day: day)))
            XCTAssertTrue(workflow.confirm { _ in true })
        }
    }

    func testAmbiguousUnsupportedTimeInvalidAndFailedResponsesRequireManualCorrection() async throws {
        let today = try XCTUnwrap(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let model = FakeOnDeviceLanguageModel()
        let workflow = TaskSchedulingWorkflow(now: { today }, languageModel: model)
        for answer in [FakeOnDeviceLanguageModel.SchedulingAnswer.interpretation(.ambiguous),
                       .interpretation(.unsupported), .interpretation(.includesTime), .interpretation(.invalid),
                       .interpretation(.intent(.date(year: 2026, month: 2, day: 31))), .failure] {
            workflow.choose(.weeks(1))
            workflow.schedulingDescription = "Friday at 4 pm or another uncertain day"
            model.schedulingAnswer = answer
            await workflow.interpretDescription()
            XCTAssertNotNil(workflow.message)
            XCTAssertFalse(workflow.canConfirm)
            XCTAssertFalse(workflow.confirm { _ in XCTFail("An unsuccessful interpretation must not save"); return true })
            workflow.chooseToday()
            XCTAssertTrue(workflow.confirm { $0 == today })
        }
    }

    func testPastInterpretationExplainsTodayOrAnotherDateWithoutChangingTheDay() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let past = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10)))
        let model = FakeOnDeviceLanguageModel()
        model.schedulingAnswer = .interpretation(.intent(.date(year: 2026, month: 10, day: 10)))
        let workflow = TaskSchedulingWorkflow(now: { today }, calendar: calendar, languageModel: model)
        workflow.schedulingDescription = "October 10, 2026"
        await workflow.interpretDescription()
        XCTAssertEqual(workflow.proposedDate, past)
        XCTAssertEqual(workflow.message, "Choose Today or another date. This day has passed.")
        XCTAssertFalse(workflow.confirm { _ in XCTFail("Past date must not save"); return true })
        workflow.chooseToday()
        XCTAssertTrue(workflow.confirm { $0 == today })
    }

    func testEveryUnavailableModelStateKeepsManualSchedulingAvailable() async throws {
        let model = FakeOnDeviceLanguageModel()
        let workflow = TaskSchedulingWorkflow(languageModel: model)
        for reason in [OnDeviceLanguageAvailability.Reason.deviceNotEligible, .appleIntelligenceNotEnabled,
                       .modelNotReady, .unsupportedLanguage] {
            model.availability = .unavailable(reason)
            workflow.schedulingDescription = "Friday"
            await workflow.interpretDescription()
            XCTAssertNotNil(workflow.availabilityMessage)
            XCTAssertFalse(workflow.canConfirm)
            XCTAssertTrue(model.receivedSchedulingDescriptions.isEmpty)
            workflow.choose(.weeks(1))
            XCTAssertTrue(workflow.confirm { _ in true })
            workflow.proposedDate = workflow.today
            XCTAssertTrue(workflow.confirm { $0 == workflow.today })
        }
    }

    func testWholeDescriptionAndContextMustFitWithoutTruncatingTrailingTime() async throws {
        let model = FakeOnDeviceLanguageModel()
        model.schedulingAnswer = .interpretation(.includesTime)
        let workflow = TaskSchedulingWorkflow(languageModel: model)
        let description = String(repeating: "Friday ", count: 200) + "at 4 pm"
        workflow.schedulingDescription = description
        model.budget = 1_000
        await workflow.interpretDescription()
        XCTAssertEqual(workflow.schedulingDescription, description)
        XCTAssertTrue(model.receivedSchedulingDescriptions.isEmpty)
        XCTAssertFalse(workflow.canConfirm)
        XCTAssertEqual(workflow.message, "This description is too long. Shorten it or choose a date.")
        model.budget = 10_000
        await workflow.interpretDescription()
        XCTAssertEqual(model.receivedSchedulingDescriptions, [description])
        XCTAssertEqual(workflow.message, "Scheduling supports calendar days only, without times. Choose a day or a date.")
        XCTAssertFalse(workflow.canConfirm)
        workflow.choose(.months(1))
        XCTAssertTrue(workflow.confirm { _ in true })
    }

    func testInputChangeManualChoicesAndCancellationDiscardLateResponses() async throws {
        let model = FakeOnDeviceLanguageModel()
        model.holdsSchedulingRequests = true
        model.schedulingAnswer = .interpretation(.intent(.weeks(1)))
        let workflow = TaskSchedulingWorkflow(languageModel: model)
        for action in 0..<3 {
            workflow.schedulingDescription = "one week out"
            let preview = workflow.proposedDate
            let request = Task { await workflow.interpretDescription() }
            await waitForRequest(model, count: action + 1)
            XCTAssertTrue(workflow.isInterpreting)
            XCTAssertFalse(workflow.confirm { _ in XCTFail("Pending interpretation must not save"); return true })
            switch action {
            case 0: workflow.schedulingDescription = "a different description"
            case 1: workflow.chooseToday()
            default: workflow.cancel()
            }
            model.finishPendingSchedulingRequest(at: action)
            await request.value
            XCTAssertEqual(workflow.proposedDate, action == 1 ? workflow.today : preview)
            XCTAssertEqual(workflow.canConfirm, action == 1)
            XCTAssertFalse(workflow.isInterpreting)
        }
    }

    func testOlderResponseCannotOverwriteANewerInterpretedPreview() async throws {
        let model = FakeOnDeviceLanguageModel()
        model.holdsSchedulingRequests = true
        model.schedulingAnswer = .interpretation(.intent(.weeks(1)))
        let workflow = TaskSchedulingWorkflow(languageModel: model)
        workflow.schedulingDescription = "one week out"
        let oldRequest = Task { await workflow.interpretDescription() }
        await waitForRequest(model, count: 1)
        model.schedulingAnswer = .interpretation(.intent(.months(1)))
        workflow.schedulingDescription = "one month out"
        let newRequest = Task { await workflow.interpretDescription() }
        await waitForRequest(model, count: 2)
        model.finishPendingSchedulingRequest(at: 1)
        await newRequest.value
        let latestPreview = workflow.proposedDate
        XCTAssertTrue(workflow.canConfirm)
        model.finishPendingSchedulingRequest(at: 0)
        await oldRequest.value
        XCTAssertEqual(workflow.proposedDate, latestPreview)
        XCTAssertTrue(workflow.canConfirm)
    }

    func testDelayedResponseUsesCapturedTodayAndConfirmationRechecksTheCurrentDay() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let capturedToday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 11)))
        let tomorrow = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        var now = capturedToday
        let model = FakeOnDeviceLanguageModel()
        model.holdsSchedulingRequests = true
        model.schedulingAnswer = .interpretation(.intent(.days(1)))
        let locale = Locale(identifier: "en_US")
        let workflow = TaskSchedulingWorkflow(now: { now }, calendar: calendar, languageModel: model, locale: locale)
        workflow.schedulingDescription = "tomorrow"
        let request = Task { await workflow.interpretDescription() }
        await waitForRequest(model, count: 1)
        now = tomorrow
        model.finishPendingSchedulingRequest()
        await request.value
        XCTAssertEqual(workflow.proposedDate, tomorrow)
        XCTAssertEqual(model.receivedSchedulingContexts.first?.today, capturedToday)
        XCTAssertEqual(model.receivedSchedulingContexts.first?.calendar, calendar)
        XCTAssertEqual(model.receivedSchedulingContexts.first?.locale, locale)
        now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 13)))
        XCTAssertFalse(workflow.confirm { _ in XCTFail("Preview became past after midnight"); return true })
    }

    func testTimeZoneChangeWhileInterpretingCannotPublishAnObsoleteCalendarDay() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Detroit"))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-11T23:00:00Z"))
        let model = FakeOnDeviceLanguageModel()
        model.holdsSchedulingRequests = true
        model.schedulingAnswer = .interpretation(.intent(.days(1)))
        let workflow = TaskSchedulingWorkflow(now: { now }, calendarProvider: { calendar }, languageModel: model)
        let initialPreview = workflow.proposedDate
        workflow.schedulingDescription = "tomorrow"
        let request = Task { await workflow.interpretDescription() }
        await waitForRequest(model, count: 1)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        model.finishPendingSchedulingRequest()
        await request.value
        XCTAssertEqual(workflow.proposedDate, initialPreview)
        XCTAssertFalse(workflow.canConfirm)
        XCTAssertEqual(workflow.message, "Calendar settings changed. Interpret again or choose a date.")
        XCTAssertEqual(model.receivedSchedulingContexts.first?.calendar.timeZone.identifier, "America/Detroit")
        workflow.chooseToday()
        XCTAssertTrue(workflow.confirm { $0 == workflow.today })
    }

    func testManualDatePickerCorrectionInvalidatesAnInFlightInterpretation() async throws {
        let model = FakeOnDeviceLanguageModel()
        model.holdsSchedulingRequests = true
        model.schedulingAnswer = .interpretation(.intent(.months(1)))
        let workflow = TaskSchedulingWorkflow(languageModel: model)
        workflow.schedulingDescription = "one month out"
        let request = Task { await workflow.interpretDescription() }
        await waitForRequest(model, count: 1)
        let pickedDate = try XCTUnwrap(workflow.calendar.date(byAdding: .day, value: 2, to: workflow.today))
        workflow.proposedDate = pickedDate
        model.finishPendingSchedulingRequest()
        await request.value
        XCTAssertEqual(workflow.proposedDate, pickedDate)
        XCTAssertTrue(workflow.confirm { $0 == pickedDate })
    }

    func testAvailabilityLossDuringARequestDoesNotReplaceThePreview() async throws {
        let model = FakeOnDeviceLanguageModel()
        model.holdsSchedulingRequests = true
        model.schedulingAnswer = .interpretation(.intent(.weeks(1)))
        let workflow = TaskSchedulingWorkflow(languageModel: model)
        let originalPreview = workflow.proposedDate
        workflow.schedulingDescription = "one week out"
        let request = Task { await workflow.interpretDescription() }
        await waitForRequest(model, count: 1)
        model.availability = .unavailable(.modelNotReady)
        model.finishPendingSchedulingRequest()
        await request.value
        XCTAssertEqual(workflow.proposedDate, originalPreview)
        XCTAssertFalse(workflow.canConfirm)
        XCTAssertEqual(workflow.message, workflow.availabilityMessage)
        workflow.choose(.months(1))
        XCTAssertTrue(workflow.confirm { _ in true })
    }

    func testBlankDescriptionAndContextBudgetFailureCannotConfirmAnEarlierChoice() async {
        let model = FakeOnDeviceLanguageModel()
        let workflow = TaskSchedulingWorkflow(languageModel: model)
        workflow.choose(.weeks(1))
        workflow.schedulingDescription = "   "
        await workflow.interpretDescription()
        XCTAssertFalse(workflow.canConfirm)
        XCTAssertTrue(model.receivedSchedulingDescriptions.isEmpty)
        workflow.schedulingDescription = "Friday"
        model.budget = "Friday".count
        await workflow.interpretDescription()
        XCTAssertTrue(model.receivedSchedulingDescriptions.isEmpty)
        XCTAssertEqual(workflow.schedulingDescription, "Friday")
        XCTAssertFalse(workflow.confirm { _ in XCTFail("The complete request must fit, including calendar context"); return true })
        workflow.chooseToday()
        XCTAssertTrue(workflow.canConfirm)
    }

    func testCancelledInterpretationTaskCannotPublishAPreview() async {
        let model = FakeOnDeviceLanguageModel()
        model.holdsSchedulingRequests = true
        model.schedulingAnswer = .interpretation(.intent(.months(1)))
        let workflow = TaskSchedulingWorkflow(languageModel: model)
        let originalPreview = workflow.proposedDate
        workflow.schedulingDescription = "one month out"
        let request = Task { await workflow.interpretDescription() }
        await waitForRequest(model, count: 1)
        request.cancel()
        model.finishPendingSchedulingRequest()
        await request.value
        XCTAssertEqual(workflow.proposedDate, originalPreview)
        XCTAssertFalse(workflow.canConfirm)
        XCTAssertFalse(workflow.isInterpreting)
    }

    private func waitForRequest(_ model: FakeOnDeviceLanguageModel, count: Int) async {
        for _ in 0..<1_000 {
            if model.receivedSchedulingDescriptions.count >= count { return }
            await Task.yield()
        }
        XCTFail("Scheduling request did not reach the model")
    }

}
