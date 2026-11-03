import Foundation

enum ProviderDefaultCatalog {
    /// Built-in providers in `ProviderModuleRegistry.allModules` order. Official
    /// relay sites are expanded by the relay module (`ProviderModule+Relay.swift`).
    static var allDefaultProviders: [ProviderDescriptor] {
        ProviderModuleRegistry.allModules.flatMap { $0.defaultDescriptors() }
    }
}
