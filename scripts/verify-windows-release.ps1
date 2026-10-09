param(
    [Parameter(Mandatory)][string]$Zip,
    [Parameter(Mandatory)][string]$Checksum,
    [Parameter(Mandatory)][string]$Fixture,
    [Parameter(Mandatory)][string]$ExpectedCommit,
    [Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$ExpectedVersion = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Release regression must execute the published EXE on Windows.' }
$zipPath = (Resolve-Path $Zip).Path
$out = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path $out) { throw "Regression output already exists: $out" }
$hash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumText = (Get-Content $Checksum -Raw).Trim()
if ($checksumText -notmatch '^([a-fA-F0-9]{64})\s+VoiceInput-windows-x64\.zip$') { throw 'Invalid release checksum format.' }
if ($hash -ne $Matches[1].ToLowerInvariant() -or $hash -ne $ExpectedSha256.ToLowerInvariant()) { throw 'Published ZIP checksum mismatch.' }
New-Item -ItemType Directory -Path $out | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $out
$package = Join-Path $out 'VoiceInput 语音输入'
$info = Get-Content (Join-Path $package 'build-info.json') -Raw | ConvertFrom-Json
if ($info.sourceCommit -ne $ExpectedCommit -or $info.runtime -ne 'win-x64' -or
    $info.sdkVersion -ne '10.0.401' -or $info.runtimeVersion -ne '10.0.12' -or
    $info.desktopRuntimeVersion -ne '10.0.12' -or
    $info.whisperCommit -ne 'a8d002cfd879315632a579e73f0148d06959de36') { throw 'Published build metadata mismatch.' }
if ($ExpectedVersion) {
    $exeVersion = (Get-Item (Join-Path $package 'VoiceInput.exe')).VersionInfo.ProductVersion
    if ($info.appVersion -ne $ExpectedVersion -or -not $exeVersion.StartsWith($ExpectedVersion, [StringComparison]::Ordinal)) { throw 'Published EXE/application version mismatch.' }
    if ((Get-Item (Join-Path $package '使用说明.md')).Length -eq 0) { throw 'Missing user instructions.' }
}
$model = Join-Path $package 'models/ggml-small.bin'
$modelHash = (Get-FileHash $model -Algorithm SHA256).Hash.ToLowerInvariant()
if ((Get-Item $model).Length -ne 487601967 -or
    $modelHash -ne '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b' -or
    $info.modelSha256 -ne $modelHash) { throw 'Published model size/hash mismatch.' }
foreach ($name in @('VoiceInput-LICENSE.txt', 'whisper.cpp-MIT.txt', 'OpenAI-Whisper-MIT.txt', 'NAudio-MIT.txt',
    'dotnet-MIT.txt', 'dotnet-THIRD-PARTY-NOTICES.txt', 'dotnet-wpf-MIT.txt', 'dotnet-wpf-THIRD-PARTY-NOTICES.txt',
    'dotnet-winforms-MIT.txt', 'dotnet-winforms-THIRD-PARTY-NOTICES.txt')) {
    if ((Get-Item (Join-Path $package "licenses/$name")).Length -eq 0) { throw "Empty license: $name" }
}
# Exercise the published backend with Unicode in model, WAV and output paths.
$unicodeFixture = Join-Path $out '输入 音频 JFK.wav'
Copy-Item $Fixture $unicodeFixture
if ((Get-FileHash $unicodeFixture).Hash.ToLowerInvariant() -ne '59dfb9a4acb36fe2a2affc14bacbee2920ff435cb13cc314a08c13f66ba7860e') { throw 'Pinned JFK fixture hash mismatch.' }
Write-Host "Published ZIP SHA256: $hash"
Write-Host "Published source commit: $($info.sourceCommit)"
& (Join-Path $PSScriptRoot 'verify-windows.ps1') -PackageDirectory $package -Fixture $unicodeFixture
if (-not $?) { throw 'Published EXE regression failed.' }
@{ zipSha256 = $hash; sourceCommit = $info.sourceCommit; modelSha256 = $modelHash;
   unicodeAudioPath = 'passed'; licenses = 'passed'; publishedPackage = 'passed';
   expectedAppVersion = $ExpectedVersion;
   humanMicrophone = 'not tested'; textInjection = 'not tested'; timestampUtc = [DateTime]::UtcNow.ToString('o') } |
    ConvertTo-Json | Set-Content (Join-Path $out 'verification/release-regression.json') -Encoding utf8
Write-Host 'Published Windows ZIP regression passed; human acceptance remains pending.'
