import Foundation

/// Per-provider plan/tier name normalization applied by `PlanTypeDisplayFormatter`.
enum PlanTypeDisplayStyle: Sendable, Equatable {
    /// Common plan names ("PRO" -> "Pro"), otherwise title-cased words.
    case titleCased
    /// Shown exactly as reported after enum-prefix stripping.
    case verbatim
    /// Kimi membership level naming.
    case kimi
    /// Cursor membership naming.
    case cursor
    /// Grok / Grok Bot subscription naming.
    case grok
    /// Trae: strips the "plan" keyword, then common plan names, otherwise verbatim.
    case trae
}
