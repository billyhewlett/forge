# AIForge Custom Build Context

This branch (`aiforge-custom`) contains all customizations for the AIForge cube draft APK
for a Pixel 9 Pro XL. Hand this file to Claude Code on the desktop as starting context.

---

## Goal

Build a custom MTG Forge Android APK that supports a 285-card singleton cube draft
called "AIForge" with 6 players. The cube includes conspiracy cards (Advantageous
Proclamation, Backup Plan, Double Stroke) and custom cards (Gleemox).

---

## What's In This Branch

### New files (cube/draft config)
- `forge-gui/res/cube/AIForge.dck` — 282 main + 3 conspiracy cards, no set codes, UTF-8 LF
- `forge-gui/res/draft/AIForge.draft` — Singleton, 6 players, 3 packs of 15, CustomRankings
- `forge-gui/res/draft/AIForgeRankings.txt` — 287 entries, #1 Black Lotus, #2 Gleemox
- `forge-gui/res/cube/AADoubleForge.dck` — secondary cube (keep, don't modify)
- `forge-gui/res/draft/AADoubleForge.draft` / `AADoubleForgeRankings.txt` — same

### Modified card scripts
- `forge-gui/res/cardsfolder/g/gleemox.txt` — removed `DeckLimit:0` ban
- `forge-gui/res/cardsfolder/b/booster_tutor.txt` — changed to library search (WORK IN PROGRESS, still buggy — see below)

### PR #10292 — Lore Seeker surplus (cube-first booster logic)
- `forge-core/.../UnOpenedProduct.java` — added `getRemainingCards()`
- `forge-gui/.../BoosterDraft.java` — cubeProduct/cubeSurplus fields, addBooster() override
- `forge-gui/.../IBoosterDraft.java` — default `addBooster()` returning null

### PR #10291 — Cogwork Librarian UI
- `forge-gui/.../LimitedPlayer.java`:
  - `public boolean cogworkLibrarianActivatedByUI = false`
  - `hasCogworkLibrarianAvailable()` checks playerFlags
  - `handleCogworkLibrarian()` reads and resets the UI flag
  - Critical bug fix: `draftCard()` was returning `true` instead of `return passPack`
- `forge-gui-mobile/.../FDeckEditor.java`:
  - Shows "[Cogwork Librarian active]" in pack title caption
  - Adds "Pick + Cogwork Librarian" menu item only when `pack.size() > 1` (guards last-card edge case)
- `forge-gui/res/languages/en-US.properties` — added `lblUseCogworkLibrarian` key

### PR #10372 — Conspiracy cards in draft
- `forge-gui/.../CustomLimited.java` — merges all DeckSection values (not just Main) into cube pool
- `forge-gui/.../GauntletMini.java` — calls `pl.assignConspiracies()` before starting match

### Android build
- `forge-gui-android/pom.xml` — `skip-d8` profile disables D8 mojo for Windows build
- `.mvn/jvm.config` — `--add-opens` for Java 22 APK signing

---

## Build Pipeline (Windows, this laptop)

```powershell
# Short-path junctions required (cmd.exe 8191-char D8 limit workaround)
# C:\f -> C:\Users\billy\Documents\forge
# C:\m2 -> C:\Users\billy\.m2
# C:\sdk -> Android SDK
# C:\jdk -> JDK

# 1. Maven (skip D8)
mvn -f C:\f\pom.xml -pl forge-gui-android -am clean package -P skip-d8 -DskipTests

# 2. D8 (PowerShell — 32767-char limit)
# [see previous session for full D8 arg array]

# 3. Sign
java -jar uber-apk-signer.jar --apks forge-android.apk --debug

# 4. Install
adb install -r forge-android-debugSigned.apk
```

### Files to push to device after build
```powershell
adb push forge-gui/res/draft/AIForgeRankings.txt /sdcard/Android/data/forge.app/files/draft/
adb push forge-gui/res/draft/AIForge.draft /sdcard/Android/data/forge.app/files/draft/
adb push forge-gui/res/cube/AIForge.dck /sdcard/Android/data/forge.app/files/cube/
adb push forge-gui/res/cardsfolder/g/gleemox.txt /sdcard/Android/data/forge.app/files/cardsfolder/g/
adb push forge-gui/res/cardsfolder/b/booster_tutor.txt /sdcard/Android/data/forge.app/files/cardsfolder/b/
```

---

## Known Issues / Pending Work

### Booster Tutor (TABLED — top priority for desktop session)
- Current implementation in `booster_tutor.txt` uses `ChangeZone` to search own library
- Bug: shows cards from all players' libraries (non-cube cards appear), not just cube pool
- **The desktop had a working implementation** — that's the fix to apply here
- The laptop Claude Code attempted `AllLibraries` param in `MakeCardEffect.java` but it shows non-cube cards
- Correct behavior: present a selection of cards from the cube's remaining card pool

### Conspiracy cards (believed working, low sample rate)
- Only 3 conspiracy cards out of 285 total (~1%) — statistically rare to see them
- Backup Plan: should give extra opening hand option; GauntletMini.assignConspiracies() fix applied
- Advantageous Proclamation: extra card in deck (20 instead of 15 sideboard limit check bypass)
- Double Stroke: copies next instant or sorcery

### Oracle of the Alpha
- Not yet implemented (requires showing 9 power cards for selection)

---

## Card Rankings Summary
- #1 Black Lotus, #2 Gleemox, #3 Mox Sapphire ... top 15 are power/moxen/staples
- #16 Advantageous Proclamation, #26 Backup Plan, #39 Double Stroke (conspiracy cards at power level)
- #147 Booster Tutor (at Liliana of the Veil's old slot)
- #284 Lore Seeker, #285 Outland Liberator (bottom)
- Cogwork Librarian: NOT in rankings (score 0, AI won't pick it)

---

## AIForge.dck structure
```
[metadata]
Name:AIForge

[main]
1 Black Lotus
... (282 cards, no set codes)

[Conspiracy]
1 Advantageous Proclamation
1 Backup Plan
1 Double Stroke
```
File must be UTF-8 no-BOM with LF line endings (not CRLF).
