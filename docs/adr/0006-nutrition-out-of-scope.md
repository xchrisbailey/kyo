# 6. Nutrition is out of scope

Status: accepted

## Context

Kyo's Today screen carried a Meals section: sample meals, macro progress bars and a "kcal logged"
summary stat. It was static placeholder UI, with no model, storage or sync behind it. The user
now tracks nutrition in a separate app.

## Decision

Food and macro tracking is out of scope for Kyo. The placeholder Meals section and the kcal
summary stat were removed from the iPhone, iPad and Watch Today screens.

If Kyo ever shows nutrition again, it will read it from HealthKit and keep no records of its own.

## Consequences

- The Today summary shows only Tasks and Habits.
- Kyo has no nutrition model, storage or sync to maintain.
- Showing nutrition later means a HealthKit integration, which needs its own decision.
