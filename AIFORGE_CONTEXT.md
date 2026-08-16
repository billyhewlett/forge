# AIForge Custom Build Context

This branch (`aiforge-custom`) contains all customizations for the AIForge cube draft APK
for a Pixel 9 Pro XL. Hand this file to Claude Code on desktop or laptop as starting context.

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
- `forge-gui/res/cardsfolder/b/booster_tutor.txt` — Spellbook workaround (see Known Issues)

### Shared signing keystore
- `forge-gui-android/aiforge.keystore` — PKCS12, alias `androiddebugkey`, pass `android`
  Both laptop and desktop must sign with this file to allow `adb install -r` upgrades.

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
  - Adds "Pick + Cogwork Librarian" menu item only when `pack.size() > 1`
- `forge-gui/res/languages/en-US.properties` — added `lblUseCogworkLibrarian` key

### PR #10372 — Conspiracy cards in draft
- `forge-gui/.../CustomLimited.java` — merges all DeckSection values into cube pool
- `forge-gui/.../GauntletMini.java` — calls `pl.assignConspiracies()` before starting match

### AI drafting fix — `AI:RemoveDeck:All` suppression
- `forge-gui/.../CardRanker.java` line 101:
  ```java
  if (card.getRules().getAiHints().getRemAIDecks() && IBoosterDraft.CUSTOM_RANKINGS_FILE[0] == null) {
  ```
  Without this fix, any cube card with `AI:RemoveDeck:All` in its card script gets a -20
  draft score penalty that overrides custom rankings. Flash (ranked #54) was picked lower
  than blue cards ranked #100+ because of this flag. The fix skips the penalty when a
  custom rankings file is active.

### Android build
- `forge-gui-android/pom.xml` — `skip-d8` profile disables D8 mojo for Windows build
- `.mvn/jvm.config` — `--add-opens` for Java 22 APK signing

---

## Build Pipeline (Windows)

Use the script: `forge-gui-android/build-aiforge.ps1`

```powershell
cd C:\Users\billy\Documents\forge\forge-gui-android
.\build-aiforge.ps1           # full build + install
.\build-aiforge.ps1 -PushOnly # just push data files (no recompile)
```

### Manual steps if the script isn't working

**Prerequisites (short-path junctions — cmd.exe 8191-char limit workaround)**
```powershell
New-Item -ItemType Junction -Path C:\f   -Target C:\Users\billy\Documents\forge
New-Item -ItemType Junction -Path C:\sdk -Target C:\Users\billy\AppData\Local\Android\Sdk
New-Item -ItemType Junction -Path C:\jdk -Target "C:\Program Files\Eclipse Adoptium\jdk-..."
```

**Step 1 — Maven**
```powershell
mvn -f C:\f\pom.xml -pl forge-gui-android -am package -P android-debug,skip-d8 -DskipTests
```
Produces `target/*_obfuscated.jar` (~19.5 MB fat-jar) and a base APK shell.

**Step 2 — D8**
```powershell
$d8 = @("--release","--min-api","26","--lib","C:\sdk\platforms\android-35\android.jar",
        "--output","C:\f\forge-gui-android\target",
        "C:\f\forge-gui-android\target\forge-android-2.0.14-SNAPSHOT-07.19_obfuscated.jar")
& C:\jdk\bin\java.exe -cp C:\sdk\build-tools\35.0.0\lib\d8.jar com.android.tools.r8.D8 @d8
```

**Step 3 — Inject DEX**
```powershell
cd C:\f\forge-gui-android\target
Copy-Item forge-android-*.apk forge-android-aiforge.apk
& C:\jdk\bin\jar.exe uf forge-android-aiforge.apk classes.dex classes2.dex
```

**Step 4 — Sign**
```powershell
& C:\jdk\bin\java.exe -jar C:\Users\billy\Documents\forge\forge-gui-android\tools\uber-apk-signer.jar `
    --apks forge-android-aiforge.apk `
    --ks C:\Users\billy\Documents\forge\forge-gui-android\aiforge.keystore `
    --ksAlias androiddebugkey --ksPass android --ksKeyPass android
```

**Step 5 — Install**
```powershell
adb install -r forge-android-aiforge-aligned-debugSigned.apk
```

**Step 6 — Push data files**

**IMPORTANT (found 2026-08-15, cost an entire debugging session):** Forge Android reads
`.dck`/`.draft`/rankings/`cardsfolder` files **only** from the OBB bundle path
(`/sdcard/Android/obb/<pkg>/Forge/res/...`), never from `/sdcard/Android/data/<pkg>/files/...`.
`ForgeConstants.DECK_CUBE_DIR`, `DRAFT_DIR`, and `CARD_DATA_DIR` are all built from `RES_DIR`,
which on Android resolves to the OBB path (confirmed via `Forge.java` — `assetDir0` passed in
at app start literally *is* the OBB directory). Pushing to `data/.../files/...` (the old
version of this step, below for reference) silently writes to a path the app never reads for
these file types — any fix pushed that way appears to do nothing, no error, no warning. This
was mistaken for caching bugs, preference bugs, and lost git history multiple times before the
real cause was found. The only path constant that legitimately lives under `data/.../files/` is
device preferences (`forge.preferences`), which is why that mechanism always worked correctly.

```powershell
$b = "/sdcard/Android/obb/forge.app/Forge/res"
adb push forge-gui/res/draft/AIForge.draft             $b/draft/AIForge.draft
adb push forge-gui/res/draft/AIForgeRankings.txt       $b/draft/AIForgeRankings.txt
adb push forge-gui/res/cube/AIForge.dck                $b/cube/AIForge.dck
adb push forge-gui/res/cardsfolder/g/gleemox.txt       $b/cardsfolder/g/gleemox.txt
adb push forge-gui/res/cardsfolder/b/booster_tutor.txt $b/cardsfolder/b/booster_tutor.txt
```

Always force-stop the app after pushing (`adb shell am force-stop <pkg>`) — a background/foreground
cycle alone does not guarantee a re-read of these files.

<details>
<summary>Old (wrong) path — kept for reference only, do not use</summary>

```powershell
$b = "/sdcard/Android/data/forge.app/files"
adb push forge-gui/res/draft/AIForge.draft             $b/draft/AIForge.draft
adb push forge-gui/res/draft/AIForgeRankings.txt       $b/draft/AIForgeRankings.txt
adb push forge-gui/res/cube/AIForge.dck                $b/cube/AIForge.dck
adb push forge-gui/res/cardsfolder/g/gleemox.txt       $b/cardsfolder/g/gleemox.txt
adb push forge-gui/res/cardsfolder/b/booster_tutor.txt $b/cardsfolder/b/booster_tutor.txt
```
</details>

---

## Build Gotchas (hard-won lessons)

### 1. Maven profiles: BOTH are required
- `-P android-debug,skip-d8` — both profiles must be present
- Without `android-debug`: produces only a small module JAR (~112KB), no APK
- Without `skip-d8`: Maven's D8 mojo runs (fails or produces stale DEX on Windows)

### 2. D8 must run on the fat-jar, not the module jar
- Correct input: `*_obfuscated.jar` (~19.5 MB — ProGuard fat-jar with all dependencies)
- Wrong input: `forge-android-*.jar` without `_obfuscated` suffix (~112 KB module-only jar)
- With the wrong jar: `classes.dex` is ~98KB. App loads but crashes immediately at startup.

### 3. Use `android-35`, not `android-34`
- `C:\sdk\platforms\android-35\android.jar` exists
- `C:\sdk\platforms\android-34\android.jar` does NOT exist on this machine

### 4. Use `jar uf` for DEX injection, NOT .NET ZipFile
- `.NET System.IO.Compression.ZipFile` / `Compress-Archive` corrupts ZIP extra-field headers
- zipalign needs these headers to pad entries to 4-byte alignment
- Symptom 1: `INSTALL_FAILED_CONTAINER_ERROR: Failed to extract native libraries, res=-18`
- Symptom 2: `Targeting R+ requires resources.arsc stored uncompressed and aligned on 4-byte boundary`
- Fix: run `jar uf base.apk classes.dex classes2.dex` from the target/ directory (JDK jar tool)

### 5. Signing key compatibility
- If the device has an APK signed with a different keystore than what you're using now,
  `adb install -r` fails with `INSTALL_FAILED_UPDATE_INCOMPATIBLE`
- Fix: `adb uninstall forge.app` (data in `/sdcard/Android/data/forge.app/` is preserved),
  then `adb install` the new APK
- Prevention: both laptop and desktop use `aiforge.keystore` from this branch

### 6. uber-apk-signer doesn't follow Windows junctions
- Running it via `C:\f\forge-gui-android\tools\uber-apk-signer.jar` fails
- Use the real path: `C:\Users\billy\Documents\forge\forge-gui-android\tools\uber-apk-signer.jar`

### 7. `--no-incremental` flag for ADB debugging
- If install fails with a cryptic error, add `--no-incremental` to `adb install`
- Incremental install can mask the true error with a different one

### 8. Flavor-named cube cards silently get a 0/unpickable rating
- A card added to `AIForge.dck` under a flavor name (needed there so Forge picks the
  right printing/art, e.g. LTC's "White Tower of Ecthelion" for the real card
  "Karakas") will draft fine but always show up with a broken/near-zero rating.
- Root cause: `card.getName()` in Java always returns the true Oracle `Name:` from
  the card's script, never the flavor name — so a rankings entry written under the
  flavor name never matches at lookup time (`CardRanker.getRawScore()` falls through
  to `SCORE_UNPICKABLE`).
- Detection: for every cube card name, check it has a direct `Name:` match somewhere
  under `forge-gui/res/cardsfolder/` — no match means it's either a flavor name or an
  unimplemented card.
- Fix: `Downloads\rerank.py` now has a `FLAVOR_NAMES` dict at the top (key = name as
  it appears in the CubeCobra `.dck` export, value = the card's real `Name:`) that
  translates automatically for both 17lands matching and the final rankings output.
  Add new entries there as they're discovered — this will keep happening as the cube
  gets more cards from Commander/Secret Lair products with reskinned reprints.

---

## Shared Keystore Setup (for desktop)

The keystore is committed at `forge-gui-android/aiforge.keystore`.
- Format: PKCS12
- Alias: `androiddebugkey`
- Store password: `android`
- Key password: `android`

To verify on a new machine:
```powershell
& C:\jdk\bin\keytool.exe -list -v -keystore forge-gui-android\aiforge.keystore -storepass android
```
Expected alias: `androiddebugkey`. If SHA-256 matches the device's installed APK, you can
use `adb install -r` directly. If it doesn't match, uninstall first.

---

## Known Issues / Pending Work

### Booster Tutor (TABLED — top priority for desktop session)
- Current `booster_tutor.txt` uses a Spellbook with all 282 main cube cards
- This is a **workaround** — the proper fix (implemented on desktop) presents 15 random
  cards from the cube's remaining card pool (cubeSurplus in BoosterDraft.java)
- When you return to desktop: push the proper implementation to this branch
- The spellbook approach works but is unwieldy (shows all 282 cards every time)
- Note: cards with commas in names use semicolons in the Spellbook param
  (e.g. `Minsc & Boo; Timeless Heroes`)

### Cube cards with `AI:RemoveDeck:All` (post-fix still worth verifying)
The CardRanker fix suppresses the -20 penalty during custom drafts. However, these cards
may still have other AI behavior issues (the flag affects gameplay AI, not just drafting).
Known affected cards in the cube include Flash and Mystic Confluence.
To find all affected cube cards:
```powershell
# Search for AI:RemoveDeck:All in cards that appear in AIForge.dck
grep -r "AI:RemoveDeck:All" forge-gui/res/cardsfolder/ | grep -f <(cut -d' ' -f2 forge-gui/res/cube/AIForge.dck | tr '[:upper:]' '[:lower:]' | sed 's/ /_/g')
```

### Flash AI play pattern
- Flash has `AI:RemoveDeck:All` which signals the AI doesn't know how to play it
- The draft fix (CardRanker) means AI will now draft Flash, but it may still never cast it
- Per-card AI hints in card scripts (e.g. `AILogic:Flash` style params) could fix this
- Approach: whack-a-mole per problematic card

### Conspiracy cards (believed working, low sample rate)
- Only 3/285 cards (~1%) — statistically rare to see them drafted

### Oracle of the Alpha
- Not yet implemented (requires showing 9 power cards for selection)

---

## Card Rankings Summary
- `setSizes.get("CUSTOM")` = 285 (max rank in AIForgeRankings.txt = #285 Outland Liberator)
- `ReadDraftRankings.getRanking()` returns `rank / maxRank` as float 0–1
- `CardRanker.getRawScore()` converts to 0–100: `100 - (100 * rkg)`
- Non-custom cards found in the custom rankings file get `rkg /= 2` boost (half the penalty)
- #1 Black Lotus, #2 Gleemox, #3 Mox Sapphire ... top 15 are power/moxen/staples
- #16 Advantageous Proclamation, #26 Backup Plan, #39 Double Stroke
- #147 Booster Tutor, #284 Lore Seeker, #285 Outland Liberator
- Cogwork Librarian: NOT in rankings (getRawScore returns SCORE_UNPICKABLE = -100, AI won't pick)
- Strip accents when looking up card names: Lórien Revealed → Lorien Revealed (line 78 ReadDraftRankings)

---

## AIForge.dck structure
```
[metadata]
name=AIForge

[Main]
1 Black Lotus|30A
... (282 cards with set codes, or without for custom cards)

[Conspiracy]
1 Advantageous Proclamation
1 Backup Plan
1 Double Stroke
```
File must be UTF-8 no-BOM with LF line endings (not CRLF).
