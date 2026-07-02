enum AppPerformanceSettings {

    // Continuous full-screen blur/gradient animation was the clearest idle GPU
    // suspect in profiling. Keep the visual backgrounds, but make them static
    // unless this is deliberately re-enabled for A/B diagnostics.
    static let enablesContinuousPageBackgroundAnimation = false

    // Legacy AppScreen aurora backgrounds use several large blurred layers.
    // They should stay visually present, but not animate forever.
    static let enablesLegacyAuroraBackgroundAnimation = false

    #if DEBUG
    static let logsPerformanceDiagnostics = false
    static let disablesGlassCardShadows = false
    static let disablesDarkGlassGlow = false
    #else
    static let logsPerformanceDiagnostics = false
    static let disablesGlassCardShadows = false
    static let disablesDarkGlassGlow = false
    #endif
}
