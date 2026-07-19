# build-aiforge.ps1 — Full AIForge APK build + install pipeline for Windows
# Run from any directory. Requires junctions and Android SDK (see PREREQUISITES below).
#
# PREREQUISITES (one-time setup):
#   New-Item -ItemType Junction -Path C:\f   -Target C:\Users\<you>\Documents\forge
#   New-Item -ItemType Junction -Path C:\sdk -Target C:\Users\<you>\AppData\Local\Android\Sdk
#   New-Item -ItemType Junction -Path C:\jdk -Target "C:\Program Files\Eclipse Adoptium\jdk-..."
#
# USAGE:
#   .\build-aiforge.ps1            # full build + install
#   .\build-aiforge.ps1 -PushOnly  # skip build, just push data files to device

param([switch]$PushOnly)

Set-StrictMode -Off
$ErrorActionPreference = "Stop"

$FORGE       = "C:\f"
$SDK         = "C:\sdk"
$JDK         = "C:\jdk"
$TARGET      = "$FORGE\forge-gui-android\target"
$SIGNER      = "$FORGE\forge-gui-android\tools\uber-apk-signer.jar"
$KEYSTORE    = "$FORGE\forge-gui-android\aiforge.keystore"   # shared laptop+desktop keystore
$KS_ALIAS    = "androiddebugkey"
$KS_PASS     = "android"
$ANDROID_JAR = "$SDK\platforms\android-35\android.jar"
$D8_JAR      = "$SDK\build-tools\35.0.0\lib\d8.jar"

function Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

function Push-Data {
    $base = "/sdcard/Android/data/forge.app/files"
    $res  = "$FORGE\forge-gui\res"
    $files = @(
        @{ from="$res\draft\AIForge.draft";             to="$base/draft/AIForge.draft" },
        @{ from="$res\draft\AIForgeRankings.txt";       to="$base/draft/AIForgeRankings.txt" },
        @{ from="$res\cube\AIForge.dck";                to="$base/cube/AIForge.dck" },
        @{ from="$res\cardsfolder\g\gleemox.txt";       to="$base/cardsfolder/g/gleemox.txt" },
        @{ from="$res\cardsfolder\b\booster_tutor.txt"; to="$base/cardsfolder/b/booster_tutor.txt" }
    )
    foreach ($f in $files) {
        $r = adb push $f.from $f.to 2>&1 | Select-Object -Last 1
        Write-Host "  $($f.to.Split('/')[-1]): $r"
    }
}

# ── 0. Push-only shortcut ───────────────────────────────────────────────────
if ($PushOnly) {
    Step "Pushing data files only"
    Push-Data
    exit 0
}

# ── 1. Maven: compile all modules + package android APK (ProGuard runs here) ─
Step "Maven build (android-debug + skip-d8)"
# android-debug  → sets packaging=apk and runs android plugin (incl. ProGuard)
# skip-d8        → disables D8 mojo so we run D8 ourselves below
# Both profiles are REQUIRED. Without android-debug: small module JAR (~112KB), no APK.
# Without skip-d8: Maven tries to run D8 itself (fails or produces wrong output on Windows).
& mvn -f "$FORGE\pom.xml" -pl forge-gui-android -am package `
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
# uber-apk-signer does not follow Windows junctions — use the real path, not C:\f\.
$realSigner = "$FORGE\forge-gui-android\tools\uber-apk-signer.jar" -replace "^C:\\f\\", "C:\Users\billy\Documents\forge\"
if (-not (Test-Path $realSigner)) { $realSigner = $SIGNER }   # try junction path anyway
& "$JDK\bin\java.exe" -jar $realSigner `
    --apks $outApk `
    --ks $KEYSTORE `
    --ksAlias $KS_ALIAS `
    --ksPass $KS_PASS `
    --ksKeyPass $KS_PASS 2>&1 | Select-Object -Last 6
if ($LASTEXITCODE -ne 0) { throw "Signing failed" }

$signedApk = "$TARGET\forge-android-aiforge-aligned-debugSigned.apk"
if (-not (Test-Path $signedApk)) {
    $signedApk = Get-ChildItem "$TARGET\forge-android-aiforge*Signed.apk" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
Write-Host "Signed APK: $signedApk"

# ── 5. Install ───────────────────────────────────────────────────────────────
Step "Installing APK"
# On signing key mismatch: adb uninstall forge.app, then re-run.
adb install -r $signedApk 2>&1
if ($LASTEXITCODE -ne 0) { throw "adb install failed" }

# ── 6. Push data files ───────────────────────────────────────────────────────
Step "Pushing data files"
Push-Data

Step "Done"
