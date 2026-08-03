# Status Item Icon Size Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Trial every status-item symbol at a uniform 12 pt size while keeping the 22 pt menu-bar boundary and aligned 2×2 labels.

**Architecture:** Give both columns a fixed 12 pt icon slot and render every active symbol—including plug and bolt—in a 12×12 pt frame. Place rows at y=0 and y=10 so frames remain inside 22 pt, accepting a measured 2 pt frame overlap for visual trial. Keep the existing persistent views and symbol cache.

**Tech Stack:** Swift, AppKit, shell build script.

**Constraint:** The user requested a focused test only, followed by build and launch. Do not run the full regression suite and do not commit Git.

---

### Task 1: Focused icon layout test

**Files:**
- Create: `tests/StatusItemIconSizingTests.swift`
- Modify: `Pulse/UI/StatusItemView.swift`

- [ ] **Step 1: Write a focused failing test**

Instantiate the production `StatusItemView`, lay it out at its reported width, and require:

```swift
allIconFrames.allSatisfy { $0.width == 12 && $0.height == 12 }
allIconFrames.allSatisfy { $0.minY >= 0 && $0.maxY <= 22 }
bottomIcon.frame.maxY - topIcon.frame.minY == 2
```

The test identifies real production image views through stable identifiers.

- [ ] **Step 2: Run only the focused test and verify RED**

Compile `MemoryMetrics.swift`, `MetricCalculations.swift`, `StatusItemView.swift`, and `StatusItemIconSizingTests.swift` into `/tmp/pulse-status-icon-tests`, then run it. Expected: fail because the current plug is 14×10.5 pt and the other icons are 11×11 pt.

- [ ] **Step 3: Implement fixed slots and centered visual frames**

Add:

```swift
private let iconSlotWidth: CGFloat = 12
private let iconSize = NSSize(width: 12, height: 12)
```

Use the slot width for intrinsic width and label origins. Place icon frames at y=0 and y=10, while label baselines remain at y=0 and y=11. Configure every SF Symbol at 12 pt and document the intentional 2 pt frame overlap.

- [ ] **Step 4: Run only the focused test and verify GREEN**

Expected: all focused assertions pass.

### Task 2: Build and launch

**Files:**
- Modify: none beyond Task 1

- [ ] **Step 1: Run `./build.sh`**

Expected: exit code 0 and `build/Pulse.app` produced.

- [ ] **Step 2: Replace the running Pulse process and launch the build**

Resolve the exact existing PID, stop only that process if present, and run:

```bash
open /Users/hlc/Documents/PulseProject/build/Pulse.app
```

- [ ] **Step 3: Confirm the final executable is running**

Use `pgrep -af` with the exact executable path. Do not run the full feature regression suite.
