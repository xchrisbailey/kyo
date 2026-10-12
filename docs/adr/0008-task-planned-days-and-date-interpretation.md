# 8. Task planned days are calendar dates

Deferred tasks become available on a planned calendar day, rather than at an absolute timestamp or a deadline. One week out means the same weekday next week; one month out means the same calendar day next month, clamped to month-end. A saved planned day stays fixed rather than being reinterpreted from its original phrase. This preserves the user's choice across daylight-saving changes and later reopening.

Apple Intelligence extracts date intent, and calendar calculations resolve the actual day shown for confirmation. We do not trust generated date arithmetic: Apple's Foundation Models guidance supports entity extraction but cautions against math and logical reasoning. Quick choices and a date picker keep scheduling usable when the model is unavailable or uncertain. See [Apple's capabilities guidance](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models).
