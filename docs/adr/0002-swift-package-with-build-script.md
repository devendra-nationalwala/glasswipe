# Swift package plus a build script instead of a checked-in Xcode project

The app is a Swift package (`GlasswipeCore` library, `Glasswipe` executable, tests) and `scripts/build-app.sh` assembles and signs `Glasswipe.app`. This keeps the repo free of `.xcodeproj` merge noise and makes the build reproducible from the command line for anyone who forks it, while `open Package.swift` still gives Xcode previews and debugging. The cost is that the bundle's Info.plist, icon and resource-bundle placement live in the script rather than in Xcode's target settings.

## Consequences

- SwiftPM resources are looked up through `ResourceLocator`, which checks `Contents/Resources` first, because the generated `Bundle.module` accessor expects the bundle at the `.app` root, where it would break code signing.
- Signing uses a stable identity (Apple Development or the self-signed "Glasswipe Local Signing") so macOS keeps Full Disk Access across rebuilds.
