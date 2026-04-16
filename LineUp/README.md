# LineUp — Xcode Setup Guide

## Game Concept
Draw straight lines connecting dots with your finger. The steadier your hand, the higher your score (0-100 per line). Progress through levels where dots shrink and lines get thinner.

---

## Xcode Project Setup

### Step 1 — Create the Xcode Project
1. Open Xcode → **File → New → Project**
2. Choose **iOS → App**
3. Fill in:
   - **Product Name:** `LineUp`
   - **Team:** Your Apple Developer account
   - **Organization Identifier:** `com.yourname.lineup`
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Use Core Data:** ❌ (unchecked)
   - **Include Tests:** optional
4. Click **Next** → choose a save location → **Create**

### Step 2 — Add the Source Files
Delete the auto-generated `ContentView.swift` (you'll replace it) and add all provided `.swift` files by dragging them into the Xcode project navigator. Make sure **"Copy items if needed"** is checked and the correct target is selected.

The required folder structure inside the Xcode project:
```
LineUp/
├── LineUpApp.swift
├── ContentView.swift
├── Models/
│   ├── GameSettings.swift
│   └── ScoreStore.swift
├── Engine/
│   ├── ScoringEngine.swift
│   └── LevelGenerator.swift
└── Views/
    ├── MainMenuView.swift
    ├── LevelSelectView.swift
    ├── GameSelectionView.swift
    ├── GameView.swift
    ├── GameResultView.swift
    ├── ScoreboardView.swift
    └── SettingsView.swift
```

> **Tip:** In Xcode you can create Groups (yellow folders) by right-clicking in the navigator → **New Group**. Name them `Models`, `Engine`, and `Views` to match the structure above.

### Step 3 — Configure Deployment Target
1. Click the project in the navigator → select the **LineUp** target
2. **General → Minimum Deployments:** set to **iOS 17.0** (uses `ContentUnavailableView` which requires 17+)

### Step 4 — Set Device Orientation (Portrait Only — recommended)
1. In **General → Deployment Info**, uncheck **Landscape Left** and **Landscape Right**

### Step 5 — Build & Run
- Select an iPhone simulator (e.g., iPhone 16) or your physical device
- Press **⌘R**

---

## Scoring Model

For each line drawn from dot A to dot B:

```
rms = sqrt( (1/N) × Σ d_i² )
normalized = rms / |AB|
score = 100 × exp(−6 × normalized)
```

Where `d_i` is the perpendicular distance of each touch point from the ideal line AB.

| Deviation | Score |
|-----------|-------|
| 0%        | 100   |
| 2%        | ~89   |
| 5%        | ~74   |
| 10%       | ~55   |
| 20%       | ~30   |

A score of **0** is returned when the drawn path doesn't connect both dots (start or end point too far away).

---

## Game Structure

| Setting | Default | Description |
|---------|---------|-------------|
| Number of Levels | 3 | How many levels the game has |
| Games per Level | 5 | Games 1–5 = 2 to 6 dots |
| Max Dot Diameter | 40 pt | Easiest (Level 1) dot size |
| Min Dot Diameter | 12 pt | Hardest (last level) dot size |
| Max Line Thickness | 8 pt | Level 1 stroke width |
| Min Line Thickness | 2 pt | Last level stroke width |

---

## App Store Preparation (future steps)
1. Add an **App Icon** set in `Assets.xcassets`
2. Add a **Launch Screen** (or use the SwiftUI-based one in Info.plist)
3. Write a **Privacy Policy** (required even if you collect no data — state that)
4. Use **Instruments → Core Animation** to profile drawing performance
5. Consider adding **Haptic Feedback** (`UIImpactFeedbackGenerator`) on score flash
6. Add **Game Center** leaderboards via `GameKit` for public leaderboards
