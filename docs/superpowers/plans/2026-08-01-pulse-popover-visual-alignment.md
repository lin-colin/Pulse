# Pulse Popover Visual Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Pulse’s status item and popover visually align with macOS System Settings while preserving native controls, dynamic colors, and the current low-overhead architecture.

**Architecture:** Keep the existing persistent AppKit view tree. Centralize horizontal geometry inside `PopoverContentView`, render the outer surface with `windowBackgroundColor`, use semantic translucent group fills, and keep the refresh selector as a real `NSPopUpButton` without a focus ring. Add only one persistent quit group and no refresh-time allocations beyond existing text updates.

**Tech Stack:** Swift 5, AppKit (`NSStatusItem`, `NSPopover`, `NSBox`, `NSPopUpButton`, `NSButton`), shell build scripts.

**Repository rule:** This workspace is not a Git repository and the user prohibits automatic commits. Every commit step from the generic workflow is intentionally omitted.

---

## File map

- Modify `tests/MetricCalculationsTests.swift`: add real AppKit geometry, focus-ring, group-color, and status-width regression tests.
- Modify `Pulse/UI/RefreshIntervalControl.swift`: suppress the unnecessary focus ring while preserving the native popup.
- Modify `Pulse/UI/StatusItemView.swift`: add glyph and trailing safety space and compensate narrow plug symbols.
- Modify `Pulse/UI/PopoverContentView.swift`: use one horizontal layout system, three equal groups, semantic colors, larger icons, and a full-row quit target.
- Modify `docs/superpowers/specs/2026-08-01-pulse-popover-visual-alignment-design.md`: append exact verification evidence after implementation.

### Task 1: Refresh selector focus behavior

**Files:**
- Modify: `tests/MetricCalculationsTests.swift`
- Modify: `Pulse/UI/RefreshIntervalControl.swift`

- [ ] **Step 1: Add a failing assertion to the real refresh-control test**

Locate the descendant `NSPopUpButton` and require no focus ring while retaining five menu items:

```swift
let popup = control.subviews.compactMap { $0 as? NSPopUpButton }.first
expectTrue(
    popup?.focusRingType == .none,
    "refresh popup should not show a persistent blue focus ring"
)
expectEqual(
    Double(popup?.numberOfItems ?? 0),
    5,
    "focus styling must not replace the native five-item popup"
)
```

- [ ] **Step 2: Run the suite and verify RED**

Run: `./test.sh`  
Expected: FAIL only on `refresh popup should not show a persistent blue focus ring` because the current button uses AppKit’s default focus-ring type.

- [ ] **Step 3: Apply the minimal native-control fix**

In `configurePopUpButton()` add:

```swift
// 为什么：菜单栏瞬时面板不需要常驻键盘焦点蓝框，但仍保留原生菜单与辅助功能。
popUpButton.focusRingType = .none
```

- [ ] **Step 4: Run the suite and verify GREEN**

Run: `./test.sh`  
Expected: all assertions pass and interval selection still reports `5`.

### Task 2: Status-item suffix safety and icon balance

**Files:**
- Modify: `tests/MetricCalculationsTests.swift`
- Modify: `Pulse/UI/StatusItemView.swift`

- [ ] **Step 1: Add a failing long-value geometry test**

After updating the view with `137.8 W`, `102.2 °C`, and two `100%` values, assign the returned width, lay out, and verify every label ends before a right-side safety inset:

```swift
view.frame.size.width = expanded
view.layoutSubtreeIfNeeded()
let labels = view.subviews.compactMap { $0 as? NSTextField }
let furthestLabelEdge = labels.map(\.frame.maxX).max() ?? expanded
expectTrue(
    expanded - furthestLabelEdge >= 7,
    "status item should keep at least seven points after the longest suffix"
)
```

- [ ] **Step 2: Run the suite and verify RED**

Run: `./test.sh`  
Expected: FAIL because the current symmetric five-point padding leaves less than seven points after the final label.

- [ ] **Step 3: Add explicit width safety and plug-symbol compensation**

Replace the symmetric padding with constants that account for text glyph overhang and the status-button edge:

```swift
private let leftPadding: CGFloat = 5
private let rightPadding: CGFloat = 9
private let labelSafetyWidth: CGFloat = 2
```

Use `intrinsicContentSize.width + labelSafetyWidth` for both column widths and label frames. Include `leftPadding + rightPadding` in the reported width. In `symbolImage(named:)`, configure `powerplug.fill` at a slightly larger point size and weight:

```swift
let configuration = NSImage.SymbolConfiguration(
    pointSize: name == "powerplug.fill" ? 10.5 : 9.5,
    weight: name == "powerplug.fill" ? .bold : .semibold
)
```

Add a comment explaining that the compensation corrects optical symbol bounds, not data-dependent layout.

- [ ] **Step 4: Run the suite and verify GREEN**

Run: `./test.sh`  
Expected: all assertions pass; `expanded > compact` remains true and the longest label retains at least seven points of trailing space.

### Task 3: One horizontal layout system and three equal groups

**Files:**
- Modify: `tests/MetricCalculationsTests.swift`
- Modify: `Pulse/UI/PopoverContentView.swift`

- [ ] **Step 1: Register the new geometry test in `main()`**

Add:

```swift
testPopoverGroupsAndRowsShareHorizontalGeometry()
```

- [ ] **Step 2: Add a failing real-view geometry test**

Create a 340×320 `PopoverContentView`, call `layoutSubtreeIfNeeded()`, locate the groups and representative titles/separators by identifiers, then assert equal group frames and matching row geometry:

```swift
let groupIDs = ["group.metrics", "group.controls", "group.quit"]
let groups: [NSBox] = groupIDs.compactMap {
    descendant(in: view, identifier: $0)
}
expectEqual(Double(groups.count), 3, "popover should expose three visual groups")
expectTrue(
    groups.map(\.frame.minX).allSatisfy { $0 == groups.first?.frame.minX },
    "all groups should share the same leading edge"
)
expectTrue(
    groups.map(\.frame.width).allSatisfy { $0 == groups.first?.frame.width },
    "all groups should share the same width"
)

let metricTitle: NSTextField? = descendant(in: view, identifier: "metric.power.title")
let controlTitle: NSTextField? = descendant(in: view, identifier: "control.refresh.title")
let quitTitle: NSTextField? = descendant(in: view, identifier: "control.quit.title")
let titleXs = [metricTitle, controlTitle, quitTitle].compactMap { $0?.windowPointX }
expectTrue(Set(titleXs.map { Int($0.rounded()) }).count == 1, "all row titles should align")
```

Add a small test-only `windowPointX` helper that converts each title’s origin into the root view coordinate system. Collect all boxes whose identifiers end in `.separator` and assert their converted `minX` and `maxX` pairs are identical.

Expected current failures: only two groups exist; quit title is not independently identifiable; separator endpoints are calculated in separate methods.

- [ ] **Step 3: Run the suite and verify RED**

Run: `./test.sh`  
Expected: FAIL on three-group count and shared geometry assertions.

- [ ] **Step 4: Centralize layout constants in `PopoverContentView`**

Add one nested layout namespace:

```swift
private enum Layout {
    static let outerInset: CGFloat = 10
    static let groupCornerRadius: CGFloat = 12
    static let rowLeadingInset: CGFloat = 12
    static let iconSlotWidth: CGFloat = 18
    static let titleX: CGFloat = 38
    static let trailingInset: CGFloat = 12
    static let metricRowHeight: CGFloat = 27
    static let controlRowHeight: CGFloat = 44
}
```

Set identifiers on all groups. Replace each hard-coded separator frame with one helper:

```swift
private func layoutSeparator(_ separator: NSView, y: CGFloat, width: CGFloat) {
    separator.frame = NSRect(
        x: Layout.titleX,
        y: y,
        width: width - Layout.titleX - Layout.trailingInset,
        height: 1
    )
}
```

Make metric and control rows use the same icon/title X coordinates.

- [ ] **Step 5: Add the third quit group with a full-row button target**

Replace the free-standing quit button with `quitGroup`, a visual `quitIcon`, a `quitTitle`, and a borderless full-row `quitButton` overlay. Give the visible title `control.quit.title` and the button `control.quit.button`. Keep `⌘Q`, `onQuit`, and one-action behavior unchanged.

Use these group frames in `layout()`:

```swift
quitGroup.frame = NSRect(x: 10, y: 8, width: contentWidth, height: 44)
controlsGroup.frame = NSRect(x: 10, y: 60, width: contentWidth, height: 88)
metricsGroup.frame = NSRect(x: 10, y: 156, width: contentWidth, height: 162)
```

- [ ] **Step 6: Increase optical icon sizes without changing the layout slots**

Configure metric and control symbols with medium weight. Use 15 pt for `powerplug.fill` and 13 pt for other symbols, while preserving the shared 18-point icon slot. Add comments explaining the optical compensation.

- [ ] **Step 7: Run the suite and verify GREEN**

Run: `./test.sh`  
Expected: all assertions pass; quit action and launch-switch tests remain green.

### Task 4: System Settings semantic colors

**Files:**
- Modify: `tests/MetricCalculationsTests.swift`
- Modify: `Pulse/UI/PopoverContentView.swift`

- [ ] **Step 1: Add a failing surface-color test**

Require a standard `NSView` surface rather than an active popover material, and require each group to share a translucent semantic fill:

```swift
expectFalse(
    view is NSVisualEffectView,
    "outer surface should use the system window color instead of wallpaper-tinted material"
)
let fills = groups.compactMap(\.fillColor)
expectTrue(
    fills.count == 3 && fills.dropFirst().allSatisfy { $0 == fills.first },
    "all groups should share one semantic grouped fill"
)
```

- [ ] **Step 2: Run the suite and verify RED**

Run: `./test.sh`  
Expected: FAIL because `PopoverContentView` currently subclasses `NSVisualEffectView` and only two groups exist before Task 3.

- [ ] **Step 3: Replace wallpaper material with semantic drawing**

Change `PopoverContentView` to subclass `NSView`, remove `material`, `blendingMode`, and `state`, and add:

```swift
override func draw(_ dirtyRect: NSRect) {
    NSColor.windowBackgroundColor.setFill()
    dirtyRect.fill()
}
```

Configure every group with the same dynamic fill:

```swift
box.fillColor = NSColor.labelColor.withAlphaComponent(0.045)
```

Keep `separatorColor`, `labelColor`, and `secondaryLabelColor` semantic; do not introduce fixed RGB values.

- [ ] **Step 4: Run the suite and verify GREEN**

Run: `./test.sh`  
Expected: all assertions pass in the current appearance.

### Task 5: Full verification and delivery

**Files:**
- Modify: `docs/superpowers/specs/2026-08-01-pulse-popover-visual-alignment-design.md`

- [ ] **Step 1: Run the complete verification set**

Run independently:

```bash
./test.sh
./build.sh
CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/pulse-swift-module-cache" \
SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/pulse-swift-module-cache" \
swiftc -warnings-as-errors -typecheck \
  -framework AppKit -framework IOKit -framework ServiceManagement \
  -target arm64-apple-macos13.0 \
  Pulse/App/main.swift Pulse/App/AppDelegate.swift \
  Pulse/Models/*.swift Pulse/UI/*.swift Pulse/Services/*.swift
plutil -lint Pulse/Resources/Info.plist
bash -n build.sh test.sh
```

Expected: every command exits 0; the test output contains the new exact assertion count.

- [ ] **Step 2: Render and inspect production views**

Render `PopoverContentView` at 340×320 in Aqua appearance and inspect that:

- no blue focus ring is visible;
- three equal light-gray groups are visible;
- titles and separators share horizontal coordinates;
- the quit row looks clickable;
- power status icon is optically comparable to other icons.

Render `StatusItemView` with long values and verify all suffixes plus trailing space are visible.

- [ ] **Step 3: Restart the final app and take a short memory checkpoint**

Replace the currently running development process with `build/Pulse.app`, wait for steady idle, and run `vmmap -summary` on the exact PID. Expected: layout-only changes do not materially exceed the previously measured 13.7 MB stable footprint; report the exact measured value rather than promising a fixed number.

- [ ] **Step 4: Append evidence to the design spec**

Record exact test count, build result, rendered-view observations, executable size, and memory checkpoint. Explicitly distinguish automated AppKit/render checks from any manual status-item click that the environment cannot automate.

- [ ] **Step 5: Leave the workspace uncommitted**

Do not initialize Git, commit, push, delete user files, or create a PR. Leave the verified `build/Pulse.app` ready for the user.
