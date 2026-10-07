# build-aiforge.ps1 — Full AIForge APK build + install pipeline for Windows
# Run from any directory. Paths default to this checkout, $env:ANDROID_HOME and
# $env:JAVA_HOME; override with -Forge/-Sdk/-Jdk. If the cmd.exe 8191-char limit bites
# (long checkout path), point a short junction at the checkout and pass -Forge C:\f:
#   New-Item -ItemType Junction -Path C:\f -Target <checkout>
#
# USAGE:
#   .\build-aiforge.ps1            # full build + install + full res push
#   .\build-aiforge.ps1 -PushOnly  # skip build, just push cube/draft files + cardsfolder.zip
#   .\build-aiforge.ps1 -ResOnly   # skip build, re-push the whole res/ (after a build+install)

param(
    [switch]$PushOnly,
    [switch]$ResOnly,
    [string]$Forge = (Resolve-Path "$PSScriptRoot\..").Path,
    [string]$Sdk   = $(if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "C:\sdk" }),
    [string]$Jdk   = $(if ($env:JAVA_HOME) { $env:JAVA_HOME } elseif (Test-Path "C:\jdk") { "C:\jdk" } else { "C:\Program Files\Java\jdk-22" })
)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$FORGE       = $Forge
$SDK         = $Sdk
$JDK         = $Jdk
$TARGET      = "$FORGE\forge-gui-android\target"
# uber-apk-signer does not follow Windows junctions; resolve to the real path.
$SIGNER      = (Get-Item "$FORGE\forge-gui-android\tools\uber-apk-signer.jar").FullName
$KEYSTORE    = "$FORGE\forge-gui-android\aiforge.keystore"   # shared laptop+desktop keystore
$KS_ALIAS    = "androiddebugkey"
$KS_PASS     = "android"
$ANDROID_JAR = "$SDK\platforms\android-35\android.jar"
$D8_JAR      = "$SDK\build-tools\35.0.0\lib\d8.jar"

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

# Forge on Android 11+ (SDK > 30) reads data from getObbDir()+"/Forge/", which is
# /sdcard/Android/obb/forge.app/Forge/ — NOT /sdcard/Android/data/forge.app/files/
$DEVICE_ASSETS = "/sdcard/Android/obb/forge.app/Forge"

function New-CardsfolderZip($outZip) {
    # Card scripts live inside res/cardsfolder/cardsfolder.zip on device. Build it from the
    # whole repo cardsfolder (same as the pom's android-release-packaging step), so every
    # card-script change in this branch ships — no per-card override list to keep in sync.
    # Use 'jar' (NOT .NET ZipFile — that corrupts extra-field headers).
    & "$JDK\bin\jar.exe" cMf $outZip -C "$FORGE\forge-gui\res\cardsfolder" .
    if ($LASTEXITCODE -ne 0) { throw "cardsfolder.zip build failed" }
}

function Push-Data {
    $base = "$DEVICE_ASSETS/res"
    $res  = "$FORGE\forge-gui\res"

    # Plain file pushes (cube/draft data)
    $files = @(
        @{ from="$res\draft\AIForge.draft";       to="$base/draft/AIForge.draft" },
        @{ from="$res\draft\AIForgeRankings.txt"; to="$base/draft/AIForgeRankings.txt" },
        @{ from="$res\cube\AIForge.dck";          to="$base/cube/AIForge.dck" }
    )
    foreach ($f in $files) {
        adb push $f.from $f.to | Select-Object -Last 1
        Write-Host "  Pushed $($f.to.Split('/')[-1])"
    }

    $tmp = "$env:TEMP\forge-cardsfix"
    New-Item -ItemType Directory -Force $tmp | Out-Null
    New-CardsfolderZip "$tmp\cardsfolder.zip"
    adb push "$tmp\cardsfolder.zip" "$base/cardsfolder/cardsfolder.zip" | Out-Null; Write-Host "  Pushed cardsfolder.zip"
    Remove-Item -Recurse -Force $tmp
}

function Push-Res {
    # Replace the device's whole res/ with this checkout's, stamped with the new APK's
    # build.txt/version.txt. Without this, a version bump makes the app download the stock
    # nightly assets.zip on launch, which (a) wipes AIForge.dck/.draft/rankings and our card
    # scripts and (b) doesn't match a branch built from an older/newer upstream.
    # Layout mirrors the pom's android-release-packaging assets.zip. The old res/ is kept
    # as res.old/ on device for rollback.
    $assets = "$FORGE\forge-gui-android\target\classes\assets"
    # Must equal the installed package's versionName (what Main.getVersionString() returns),
    # not target\classes\assets\version.txt, which carries an extra -MM.dd suffix.
    $version = ((adb shell dumpsys package forge.app | Select-String "versionName=") -split "=")[-1].Trim()
    if (-not $version) { throw "Could not read installed forge.app versionName" }
    $tmp = "$env:TEMP\forge-res"
    if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
    New-Item -ItemType Directory -Force "$tmp\stage\res\cardsfolder" | Out-Null
    robocopy "$FORGE\forge-gui\res" "$tmp\stage\res" /E /XD "$FORGE\forge-gui\res\cardsfolder" /XF *.xcf /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed ($LASTEXITCODE)" }
    Copy-Item "$assets\build.txt" "$tmp\stage\res\build.txt"
    New-CardsfolderZip "$tmp\stage\res\cardsfolder\cardsfolder.zip"
    & "$JDK\bin\jar.exe" cMf "$tmp\res.zip" -C "$tmp\stage" res
    if ($LASTEXITCODE -ne 0) { throw "res.zip build failed" }
    Write-Host "  res.zip: $([math]::Round((Get-Item "$tmp\res.zip").Length/1MB,1)) MB"

    adb push "$tmp\res.zip" "$DEVICE_ASSETS/res.zip" | Select-Object -Last 1
    adb shell "cd $DEVICE_ASSETS && rm -rf res.old && mv res res.old && unzip -q -o res.zip && rm res.zip && printf %s '$version' > version.txt"
    if ($LASTEXITCODE -ne 0) { throw "on-device res unpack failed" }
    Write-Host "  Device res replaced (previous kept at res.old), version.txt = $version"
    Remove-Item -Recurse -Force $tmp
}

# ── 0. Push-only shortcut ───────────────────────────────────────────────────
if ($PushOnly) {
    Step "Pushing data files only"
    adb shell am force-stop forge.app | Out-Null
    Push-Data
    adb shell am force-stop forge.app | Out-Null
    Write-Host "  Forge force-stopped — changes take effect on next launch."
    exit 0
}

if ($ResOnly) {
    Step "Pushing res only"
    adb shell am force-stop forge.app | Out-Null
    Push-Res
    adb shell am force-stop forge.app | Out-Null
    exit 0
}

# ── 1. Maven: compile all modules + package android APK (ProGuard runs here) ─
Step "Maven build (android-debug + skip-d8)"
# android-debug  → sets packaging=apk and runs android plugin (incl. ProGuard)
# skip-d8        → disables D8 mojo so we run D8 ourselves below
# Both profiles are REQUIRED. Without android-debug: small module JAR (~112KB), no APK.
# Without skip-d8: Maven tries to run D8 itself (fails or produces wrong output on Windows).
# -s: resolve local-settings.xml with absolute path (relative path in .mvn/maven.config
#     breaks when Maven is invoked from a directory other than the project root)
& mvn -f "$FORGE\pom.xml" -s "$FORGE\.mvn\local-settings.xml" `
    -pl forge-gui-android -am package `
    -P android-debug,skip-d8 -DskipTests -q
if ($LASTEXITCODE -ne 0) { throw "Maven failed" }

# Find the obfuscated jar (ProGuard fat-jar, ~19.5MB — this is the D8 input)
$obfJar = Get-ChildItem "$TARGET\*_obfuscated.jar" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $obfJar) { throw "Could not find _obfuscated.jar in $TARGET" }
Write-Host "ProGuard output: $($obfJar.Name) ($([math]::Round($obfJar.Length/1MB,1)) MB)"

# Find the base APK (resources + manifest shell — DEX inside may be stale, we replace it)
$baseApk = Get-ChildItem "$TARGET\forge-android-*.apk" |
    Where-Object { $_.Name -notlike "*signed*" -and $_.Name -notlike "*aligned*" } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $baseApk) { throw "Could not find base APK in $TARGET" }
Write-Host "Base APK: $($baseApk.Name) ($([math]::Round($baseApk.Length/1MB,1)) MB)"

# ── 2. D8: compile ProGuard jar → DEX ───────────────────────────────────────
Step "D8 (ProGuard jar → classes.dex)"
# CRITICAL: D8 must target _obfuscated.jar (the full fat-jar, ~19.5MB).
# If you accidentally run D8 on the small module jar (~112KB), classes.dex is ~98KB
# (only forge-android module classes) and the app will crash at startup.
# Use android-35/android.jar (android-34 does not exist on this machine).
$d8Args = @("--release", "--min-api", "26", "--lib", $ANDROID_JAR, "--output", $TARGET, $obfJar.FullName)
& "$JDK\bin\java.exe" -cp $D8_JAR com.android.tools.r8.D8 @d8Args 2>&1 |
    Where-Object { $_ -notmatch "^Info:" } | Select-Object -Last 5
if ($LASTEXITCODE -ne 0) { throw "D8 failed" }

Write-Host "classes.dex:  $([math]::Round((Get-Item "$TARGET\classes.dex").Length/1MB,1)) MB"
Write-Host "classes2.dex: $([math]::Round((Get-Item "$TARGET\classes2.dex").Length/1MB,1)) MB"

# ── 3. Inject DEX into APK ──────────────────────────────────────────────────
Step "Injecting DEX into APK (jar uf)"
# CRITICAL: Use 'jar uf' (JDK tool), NOT .NET ZipFile / PowerShell Compress-Archive.
# .NET ZipFile corrupts ZIP extra-field headers required by zipalign. This causes either:
#   INSTALL_FAILED_CONTAINER_ERROR: Failed to extract native libraries, res=-18
#   Targeting R+ requires resources.arsc stored uncompressed and aligned on a 4-byte boundary
# 'jar uf' preserves the existing ZIP structure, zipalign works correctly.
$outApk = "$TARGET\forge-android-aiforge.apk"
Copy-Item $baseApk.FullName $outApk -Force
Push-Location $TARGET
& "$JDK\bin\jar.exe" uf $outApk classes.dex classes2.dex 2>&1
Pop-Location
if ($LASTEXITCODE -ne 0) { throw "jar uf failed" }
Write-Host "APK with new DEX: $([math]::Round((Get-Item $outApk).Length/1MB,1)) MB"

# ── 4. Sign (zipalign + apksign) ────────────────────────────────────────────
Step "Signing APK"
# Uses the shared keystore committed to this branch (aiforge.keystore).
# BOTH laptop and desktop must use this keystore. If APKs are signed with different
# keystores, 'adb install -r' fails with INSTALL_FAILED_UPDATE_INCOMPATIBLE and you
# must 'adb uninstall forge.app' first (app data on /sdcard is preserved).
& "$JDK\bin\java.exe" -jar $SIGNER `
    --apks $outApk `
    --ks $KEYSTORE `
    --ksAlias $KS_ALIAS `
    --ksPass $KS_PASS `
    --ksKeyPass $KS_PASS 2>&1 | Select-Object -Last 6
if ($LASTEXITCODE -ne 0) { throw "Signing failed" }

# uber-apk-signer names output: <base>-signed-aligned.apk (lower-case, no "debug" prefix)
$signedApk = Get-ChildItem "$TARGET\forge-android-aiforge*signed*.apk" |
    Where-Object { $_.Name -notlike "*.idsig" } |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
Write-Host "Signed APK: $signedApk"

# ── 5. Install ───────────────────────────────────────────────────────────────
Step "Installing APK"
# Force-stop first so the new APK and card files take effect immediately on launch.
adb shell am force-stop forge.app | Out-Null
# On signing key mismatch: adb uninstall forge.app, then re-run.
# No 2>&1: under PS 5.1 + ErrorActionPreference=Stop, adb's normal stderr chatter
# ("All files should be loaded...") becomes a terminating error.
adb install -r $signedApk
if ($LASTEXITCODE -ne 0) { throw "adb install failed" }

# ── 6. Push res (card data, cube/draft files) ────────────────────────────────
Step "Pushing res to device"
Push-Res

# Force-stop again after data push so Forge re-reads card files on next launch.
adb shell am force-stop forge.app | Out-Null
Write-Host "  Forge force-stopped — changes take effect on next launch."

Step "Done"
