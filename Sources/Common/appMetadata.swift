public let stableHyprSpaceAppId: String = "dev.hyprspace"
#if DEBUG
    public let hyprSpaceAppId: String = "dev.hyprspace.debug"
    public let hyprSpaceAppName: String = "HyprSpace-Debug"
#else
    public let hyprSpaceAppId: String = stableHyprSpaceAppId
    public let hyprSpaceAppName: String = "HyprSpace"
#endif
