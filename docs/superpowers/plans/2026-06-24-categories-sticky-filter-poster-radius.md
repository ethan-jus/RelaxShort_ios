# Categories Sticky Filter And Poster Radius Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Home Categories match the DramaBox collapsed-filter behavior and make all video poster corners consistently sharp.

**Architecture:** Keep the change local to iOS Home UI. `HomeView` owns the Categories filter state and scroll-derived collapsed state; poster corner styling is centralized through `DB.posterRadius` and `CoverImageView` call sites pass dimensions before clipping where needed.

**Tech Stack:** SwiftUI, existing `DB`/`DT` design tokens, existing `CoverImageView`.

---

### Task 1: Centralize Poster Radius

**Files:**
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Core/DesignToken.swift`
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Views/Home/ContentGridView.swift`

- [ ] Set `DB.posterRadius` to `4`.
- [ ] Ensure Home Popular card covers pass `width` and `height` into `CoverImageView`, so clipping happens after the final poster size is known.
- [ ] Remove redundant outer cover `.clipped()` calls when `CoverImageView` already clips at the poster shape.

### Task 2: Categories Collapsed Summary

**Files:**
- Modify: `/Users/ethan/myspance/relaxshort/ios/v1.0.0/RelaxShort/Views/Home/HomeView.swift`

- [ ] Add Categories scroll offset tracking with a lightweight `PreferenceKey`.
- [ ] Show the full three-row filter at the top of the Categories scroll content when the user is near the top.
- [ ] When scrolled past the full filter, pin a one-line summary under the top tab bar: selected language, selected genre, selected payment, plus a down chevron.
- [ ] Tapping the summary opens the full filter panel.
- [ ] The expanded panel includes a bottom collapse button.
- [ ] Scrolling back to the top closes the overlay and shows the full filter naturally.

### Task 3: Verification

**Files:**
- iOS project under `/Users/ethan/myspance/relaxshort/ios/v1.0.0`

- [ ] Run `git diff --check`.
- [ ] Run `xcodebuild -project RelaxShort.xcodeproj -scheme RelaxShort -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build`.
- [ ] Report any visual behavior that still requires simulator confirmation.
