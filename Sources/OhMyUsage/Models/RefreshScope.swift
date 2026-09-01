/// Fan-out scope for user-initiated refreshes (optimization plan §9.4).
///
/// - `.visible`: the providers currently shown in the menu bar panel; used
///   when the menu bar panel opens.
/// - `.selected(String)`: a single provider picked in the settings page
///   detail view.
/// - `.all`: every enabled provider; used by explicit "refresh all" actions.
///
/// Scope only selects which providers participate. Manual refreshes bypass
/// snapshot TTLs but still respect the per-provider in-flight gate and the
/// global concurrency cap; the background scheduler keeps refreshing only
/// due items regardless of scope.
enum RefreshScope: Equatable, Sendable {
    case visible
    case selected(String)
    case all
}
