import SwiftUI

private struct ProjectsEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var projectsEnabled: Bool {
        get { self[ProjectsEnabledKey.self] }
        set { self[ProjectsEnabledKey.self] = newValue }
    }
}
