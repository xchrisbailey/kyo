# 9. Projects preference synchronization

Status: accepted for #265 by the lead before implementation.

Projects is an optional presentation of existing content. Its preference alone synchronizes
between iPhone and iPad using `NSUbiquitousKeyValueStore`, with a Kyo-only key-value-store
entitlement. SwiftData remains configured with `cloudKitDatabase: .none` under ADR 0004;
no task, project, or memo content is synchronized by this decision.

Each device persists a versioned preference record locally for offline use. A fresh default
is off and publishes nothing. Existing active or archived projects infer on during upgrade
only in the absence of an explicit choice. Records retain this provenance: every explicit
choice outranks every inferred migration, regardless of delivery order. Equal-provenance
records use a hybrid monotonic timestamp and stable device/record tie-breakers to converge
under concurrent edits. A stale cloud notification cannot replace a known newer winner;
the winner is republished to repair cloud state. Initialization and foreground activation
reconcile local and cloud records; change notifications reconcile subsequent deliveries.
A successful `synchronize()` request does not establish remote delivery.

The phone remains the only preference writer for Watch. Revisioned enabled state travels
through the existing single application-context publish path alongside tasks, habits, memos,
and theme (ADRs 0001–0003, 0005, 0007). Watch persists the newest revision, rejects stale
values, and retains it offline. Missing preference data from an older phone preserves the
last value or legacy project access until a preference arrives. Task command reconciliation
and availability rules remain unchanged.

Tests inject cloud/time/transport boundaries and exercise real preference persistence.
In-memory/UI launches use isolated defaults and never connect to the real cloud store.
Simulated convergence does not establish actual iCloud transport integration, which requires
supported signed devices sharing an iCloud account.

References: [Apple preference synchronization](https://developer.apple.com/documentation/foundation/synchronizing-app-preferences-with-icloud),
[NSUbiquitousKeyValueStore](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore).
