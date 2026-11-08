# Liquid Glass on macOS 26/27: what the API offers

Research for [#5](https://github.com/devendra-nationalwala/glasswipe/issues/5). Researched 2026-11-07 against Apple developer documentation, WWDC25/WWDC26 sessions, the Human Interface Guidelines and the macOS 27 release notes.

## Answer in brief

- **Most of Liquid Glass comes free with standard SwiftUI.** `NavigationSplitView` gets a floating glass sidebar. `.toolbar` items are grouped onto shared glass. Sheets, popovers, menus and standard controls take on the new look once you build with the macOS 26+ SDK.
- **Custom glass is a small API, all of it macOS 26.0+:** `glassEffect(_:in:)`, `Glass` (`.regular`, `.clear`, `.identity`, `.tint(_:)`, `.interactive(_:)`), `GlassEffectContainer`, `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)`, `glassEffectTransition(_:)`, `.buttonStyle(.glass)` / `.glassProminent`. Supporting APIs: `ToolbarSpacer`, `sharedBackgroundVisibility(_:)`, `backgroundExtensionEffect()`, `scrollEdgeEffectStyle(_:for:)` and `ConcentricRectangle`.
- **macOS 27 adds no new SwiftUI glass types.** Apple's `Glass` reference lists no 27.0 members. The changes are mostly behaviour and appearance, plus one API that needs 27:
  - The glass looks different: "more uniform refraction and improved contrast", and it follows a new system-wide Liquid Glass opacity/tint slider.
  - Sidebars reach the window edges, and selected sidebar items use semibold text.
  - Interactive glass is tuned for pointer clicks on the Mac.
  - Windows dim when inactive. Custom views can follow this with `appearsActive`.
  - Menus hide most symbol images.
  - **macOS 27 only:** `GeometryProxy.concentricCornerRadii`.
  - **macOS 27 SDK:** the `UIDesignRequiresCompatibility` opt-out is ignored, so you can no longer turn the new design off.
- **HIG patterns for a sidebar-driven utility like Glasswipe:** use `NavigationSplitView` with no more than two levels of sidebar hierarchy, SF Symbols in the sidebar, and nothing critical at the bottom of it. Use glass only in the control/navigation layer, never in the content layer, and use it sparingly. Toolbar items should be borderless symbols, with one `.prominent` primary action on the trailing side. Every toolbar command must also be in the menu bar.

Because Glasswipe's minimum is macOS 26, it can use every glass API listed here unconditionally. Only `concentricCornerRadii` needs an `if #available(macOS 27, *)` check.

---

## 1. What you get automatically

Building with the macOS 26+ SDK puts standard components on Liquid Glass with no code changes ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass); WWDC25 [Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)):

- **`NavigationSplitView`**: the sidebar floats on Liquid Glass above the content. `.inspector(isPresented:content:)` gives a more subtle layer on the trailing side.
- **Toolbars**: items are grouped automatically onto shared glass backgrounds and don't have bezels on macOS ([HIG Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars)).
- **Controls** (buttons, toggles, sliders, steppers, segmented pickers, text fields): they get the new shapes and sizes. Apple says not to hard-code layout metrics.
- **Sheets and popovers**: these are glass too. Apple tells you to *remove* any custom visual-effect backgrounds from them so they stay consistent ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)).
- **Scroll edge effect**: content scrolling under a toolbar is blurred and faded automatically.

## 2. Custom glass API (SwiftUI, macOS 26.0+)

Sources: [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views), [`glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)), [`Glass`](https://developer.apple.com/documentation/swiftui/glass), [`GlassEffectTransition`](https://developer.apple.com/documentation/swiftui/glasseffecttransition).

### `glassEffect`

```swift
nonisolated func glassEffect(
    _ glass: Glass = .regular,
    in shape: some Shape = DefaultGlassEffectShape()   // a Capsule
) -> some View
```

It draws the glass shape behind the view, anchored to the view's frame including padding, and applies the glass foreground effects (such as vibrant text) on top. Apply it **after** any other modifiers that change how the view looks.

### `Glass` (configuration)

| Member | Signature | Use |
|---|---|---|
| `regular` | `static var regular: Glass` | The default. It blurs the background and adjusts its luminosity so text stays legible. |
| `clear` | `static var clear: Glass` | Very translucent. **Only for use over visually rich media.** The HIG suggests a 35% dark dimming layer when the content behind is bright. |
| `identity` | `static var identity: Glass` | No effect. Useful for switching glass off conditionally without changing the view tree. |
| `tint(_:)` | `func tint(_ color: Color?) -> Glass` | Use a tint to carry meaning or prominence, not as decoration. |
| `interactive(_:)` | `func interactive(_ isInteractive: Bool = true) -> Glass` | Reacts to pointer and touch the same way `.buttonStyle(.glass)` does. |

```swift
Label("Reclaimable", systemImage: "internaldrive")
    .padding()
    .glassEffect(.regular.tint(.accentColor).interactive(), in: .rect(cornerRadius: 16))
```

### Grouping and morphing

```swift
struct GlassEffectContainer<Content: View>: View    // init(spacing: CGFloat? = nil, content:)
func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View
func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View
func glassEffectTransition(_ transition: GlassEffectTransition) -> some View
// GlassEffectTransition: .matchedGeometry (default within spacing), .materialize, .identity
```

- Glass shapes inside a `GlassEffectContainer` render together. They blend when they come within `spacing` of each other, and they can morph into one another.
- `glassEffectID` together with a `@Namespace` and `withAnimation` lets a shape morph in and out when views are added or removed.
- `glassEffectUnion` merges separate views into one glass shape. Use it for views that aren't siblings in an `HStack` or `VStack`.
- Apple's performance guidance: keep the amount of glass on screen low, and group it in containers rather than scattering standalone effects.

```swift
@Namespace private var ns
@State private var showActions = false

GlassEffectContainer(spacing: 20) {
    HStack(spacing: 20) {
        Button("Scan", systemImage: "magnifyingglass") { showActions.toggle() }
            .buttonStyle(.glass)
            .glassEffectID("scan", in: ns)
        if showActions {
            Button("Clean Up", systemImage: "trash") { }
                .buttonStyle(.glassProminent)
                .glassEffectID("cleanup", in: ns)
        }
    }
}
.animation(.default, value: showActions)
```

### Glass button styles

`.buttonStyle(.glass)` (`GlassButtonStyle`) and `.buttonStyle(.glassProminent)` (`GlassProminentButtonStyle`), macOS 26.0+. On macOS 26.x these styles showed no hover state outside a toolbar. That is fixed in macOS 27 ([macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes)).

## 3. Toolbars, sidebars, scroll edges and shapes (macOS 26.0+)

Sources: WWDC25 [323](https://developer.apple.com/videos/play/wwdc2025/323/), [`backgroundExtensionEffect()`](https://developer.apple.com/documentation/swiftui/view/backgroundextensioneffect()), [`scrollEdgeEffectStyle(_:for:)`](https://developer.apple.com/documentation/swiftui/view/scrolledgeeffectstyle(_:for:)), [`ConcentricRectangle`](https://developer.apple.com/documentation/swiftui/concentricrectangle), [SwiftUI updates](https://developer.apple.com/documentation/updates/swiftui).

```swift
NavigationSplitView {
    List(selection: $section) {
        Section("Clean") {
            Label("Storage", systemImage: "internaldrive").tag(Section.storage)
            Label("Memory", systemImage: "memorychip").tag(Section.memory)
        }
        Section("Apps") {
            Label("Uninstall", systemImage: "app.badge.minus").tag(Section.uninstall)
            Label("Startup Items", systemImage: "power").tag(Section.startup)
        }
    }
} detail: {
    ScrollView { DetailView(section) }
        .scrollEdgeEffectStyle(.hard, for: .top)   // .automatic / .soft / .hard
}
.toolbar {
    ToolbarItem { RescanButton() }
    ToolbarSpacer(.fixed)                          // or .flexible
    ToolbarItem { CleanUpButton() }               // the single primary action
    ToolbarItem { AccountButton() }
        .sharedBackgroundVisibility(.hidden)       // pull this item off the shared glass
}
.searchable(text: $query)                          // goes top-trailing on macOS
```

- **`backgroundExtensionEffect()`** places mirrored, blurred copies of a view in the surrounding safe area. Apply it to a hero or banner in the detail column so the image appears to continue under the sidebar or inspector. It clips the view. Apple's guidance is to use one instance at most.
- **`ToolbarSpacer(_:placement:)`** splits toolbar items into separate glass groups. Other toolbar additions from the same release:
  - `visibilityPriority(_:)` and `ToolbarOverflowMenu` decide which items stay visible as the window narrows.
  - `toolbarMinimizationBehavior(_:for:)` controls how the toolbar minimizes on scroll.
  - `badge(_:)` adds a badge to toolbar buttons.
- **`ConcentricRectangle`** and **`.rect(corner: .containerConcentric)`** give custom shapes corners that are concentric with their container, such as the window or a glass group:

  ```swift
  CustomControl().background(.tint, in: .rect(corner: .containerConcentric))
  ConcentricRectangle(uniformTopCorners: .fixed(12), uniformBottomCorners: .concentric)
  ```

- **AppKit counterparts**, for when Glasswipe needs to drop down to AppKit:
  - `NSGlassEffectView` has `style`, `tintColor`, `cornerRadius`, `effectIsInteractive` and `contentView`.
  - `NSGlassEffectContainerView` is the container.
  - Also: `NSButton.BezelStyle.glass`, `NSToolbarItem.Style.prominent`, `NSBackgroundExtensionView`, `NSSplitViewItemAccessoryViewController` and `NSControl.ControlSize.extraLarge`.

  Source: [AppKit updates](https://developer.apple.com/documentation/updates/appkit).

## 4. What changed in macOS 27

Apple does not list any new SwiftUI `Glass` or `glassEffect` API at 27.0: the [`Glass`](https://developer.apple.com/documentation/swiftui/glass) reference has only 26.0 members, and the Liquid Glass entries on the [SwiftUI updates page](https://developer.apple.com/documentation/updates/swiftui) are all June 2025. The WWDC26 SwiftUI additions there are for foldables (`ArrangementView`, hinge APIs, vertical toolbars). The macOS 27 changes are:

| Change | Kind | Source |
|---|---|---|
| Refined glass with "more uniform refraction and improved contrast". It responds automatically to the **new system Liquid Glass slider**, which sets the tint/opacity. No code changes needed. | Automatic | WWDC26 [What's new in SwiftUI](https://developer.apple.com/videos/play/wwdc2026/269/) |
| **Interactive glass on Mac**: "On macOS, like on iOS, you can mark Liquid Glass custom elements as 'interactive' … optimized to work great with the mouse pointer." Same `.interactive()` API, new click-bounce behaviour on 27. | Behaviour | WWDC26 [269](https://developer.apple.com/videos/play/wwdc2026/269/), [289](https://developer.apple.com/videos/play/wwdc2026/289/) |
| **Sidebars reach the window edges**, selected items use **semibold** text, and bordered toolbar items over the sidebar adopt glass. | Automatic | WWDC26 [Modernize your AppKit app](https://developer.apple.com/videos/play/wwdc2026/289/) |
| The scroll edge effect resolves to **hard** when there is free-floating text such as the window title. | Automatic | WWDC26 [289](https://developer.apple.com/videos/play/wwdc2026/289/) |
| **Inactive windows dim** their icons and text. Custom views should follow along with `@Environment(\.appearsActive)`. | Automatic + pattern | WWDC26 [269](https://developer.apple.com/videos/play/wwdc2026/269/) |
| **Menus hide symbol images** in the menu bar and context menus by default. Opt one back in with `.labelStyle(.titleAndIcon)`. | Automatic | [macOS 27 release notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes), WWDC26 269 |
| A `TabView` in an inspector now matches its sidebar look and uses the `.tabs` picker style. | Automatic | macOS 27 release notes |
| `.glass` / `.glassProminent` buttons now show a hover state outside toolbars (a bug fix). | Fix | macOS 27 release notes |
| **`GeometryProxy.concentricCornerRadii` / `concentricCornerRadii(in:)`** return a `RectangleCornerRadii?` for custom drawing. **macOS 27.0+ only.** | **New API (27)** | [Docs](https://developer.apple.com/documentation/swiftui/geometryproxy/concentriccornerradii) |
| AppKit: `NSView.cornerConfiguration` / `NSViewCornerConfiguration` with `.containerConcentric(_:)`, and `NSTitlebarAccessoryViewController` can now draw outside its bounds to support glass. These are AppKit-only. | New API (27, AppKit) | WWDC26 289, release notes |
| **`UIDesignRequiresCompatibility` is ignored when you build for macOS 27 or later**, so you cannot opt out of the new design. | Policy | [Docs](https://developer.apple.com/documentation/bundleresources/information-property-list/uidesignrequirescompatibility) |

```swift
// macOS 27 only
if #available(macOS 27, *) {
    GeometryReader { geo in
        Canvas { ctx, size in
            if let r = geo.concentricCornerRadii {
                ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadii: r),
                         with: .color(.accentColor.opacity(0.2)))
            }
        }
    }
}

// Custom sidebar footer that dims with the window (pattern from WWDC26)
struct SidebarFooter: View {
    @Environment(\.appearsActive) private var appearsActive
    var body: some View { ReclaimedTotalView().opacity(appearsActive ? 1 : 0.5) }
}
```

## 5. HIG patterns for a sidebar-driven utility app

From [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) (Liquid Glass guidance updated 2025-09-09), [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) (updated 2026-06-08) and [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars) (updated 2025-12-16):

- **Layers.** Glass is the functional layer that floats above content. "Don't use Liquid Glass in the content layer." The exception is transient controls such as sliders and toggles while they are being used. "Use Liquid Glass effects sparingly." For Glasswipe, the lists of Scan results and the size breakdowns are content and should not be glass. Glass belongs to the sidebar, toolbar and a few floating actions.
- **Sidebar.**
  - Show no more than two levels of hierarchy, with short group titles. This suits Glasswipe's sections: Storage Cleaner, Memory Cleaner, Uninstall, Startup Items.
  - Use SF Symbols, which follow the user's accent color by default. Use fixed colors only when they carry meaning.
  - Let people hide the sidebar. Consider collapsing it automatically when the window gets narrow.
  - Don't put critical information or actions at the bottom of the sidebar.
  - Let rich content extend underneath with `backgroundExtensionEffect()` or horizontal scrolling.
  - Row size follows the user's sidebar icon size setting.
- **Toolbar.**
  - Use system symbols without borders.
  - Give exactly one primary action the `.prominent` style, on the trailing side. For Glasswipe that is "Clean Up".
  - Keep text-labelled items apart from symbol items by putting a `ToolbarSpacer` between them.
  - Avoid custom backgrounds and tints. Use `scrollEdgeEffectStyle` to separate the toolbar from content.
  - Window titles should be under 15 characters and should not be the app name.
  - **Every toolbar item must also exist as a menu-bar command.**
- **Colour and accessibility.** Pick materials by their meaning, not their colour. Test with Reduce Transparency, Reduce Motion and Increase Contrast. On macOS 27, also test across the Liquid Glass slider range.

## Open points / caveats

- WWDC26 session pages were read through their transcript summaries. The facts on sidebar edge-to-edge and semibold selection come from the AppKit session (289). Apple presents them as system appearance changes, so SwiftUI `NavigationSplitView` should inherit them, but no SwiftUI-specific doc says so. Confirm by running the app on 27.2.
- Apple's docs give no API to read or override the user's Liquid Glass slider value. As far as the docs show, apps can't access it.
