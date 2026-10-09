param([string]$OutputDirectory = "dist/windows")
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'This build requires Windows, Visual Studio C++ tools, CMake and .NET 10 SDK.' }
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
foreach ($tool in @('git', 'cmake', 'dotnet')) { Get-Command $tool -ErrorAction Stop | Out-Null }
function Invoke-Checked([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
$whisperCommit = 'a8d002cfd879315632a579e73f0148d06959de36'
$modelHash = '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b'
$modelSize = 487601967
$out = [IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
# Do not erase or overwrite a previous package. Choose another OutputDirectory to rebuild.
if (Test-Path $out) { throw "Output already exists: $out. Choose a fresh OutputDirectory." }
$work = Join-Path $root ('build/windows-' + [guid]::NewGuid().ToString('N'))
$src = Join-Path $work 'whisper.cpp'
$nativeBuild = Join-Path $work 'native'
$package = Join-Path $out 'VoiceInput 语音输入'
New-Item -ItemType Directory -Path $work, $package -Force | Out-Null
Invoke-Checked 'git' @('clone', '--depth', '1', '--branch', 'v1.7.6', 'https://github.com/ggml-org/whisper.cpp.git', $src)
$actualCommit = (& git -C $src rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $whisperCommit) { throw 'Unexpected whisper.cpp v1.7.6 source commit.' }
# The upstream CLI uses narrow argv/file APIs. Embed UTF-8 process code page so
# Unicode installation, model and user temporary paths survive those APIs.
$utf8Manifest = (Join-Path $root 'windows/whisper-utf8.manifest').Replace('\', '/')
# Baseline x64 CPU build: avoid requiring the runner CPU's AVX extensions or a GPU.
# Static CRT and disabled OpenMP avoid an external Visual C++ runtime dependency.
Invoke-Checked 'cmake' @('-S', $src, '-B', $nativeBuild, '-G', 'Visual Studio 17 2022', '-A', 'x64',
    '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded',
    "-DCMAKE_EXE_LINKER_FLAGS=/MANIFEST:EMBED /MANIFESTINPUT:`"$utf8Manifest`"",
    '-DBUILD_SHARED_LIBS=OFF', '-DWHISPER_BUILD_TESTS=OFF', '-DWHISPER_BUILD_SERVER=OFF',
    '-DGGML_NATIVE=OFF', '-DGGML_SSE42=OFF', '-DGGML_AVX=OFF', '-DGGML_AVX2=OFF',
    '-DGGML_BMI2=OFF', '-DGGML_FMA=OFF', '-DGGML_F16C=OFF', '-DGGML_OPENMP=OFF',
    '-DGGML_CUDA=OFF', '-DGGML_VULKAN=OFF', '-DGGML_BLAS=OFF')
Invoke-Checked 'cmake' @('--build', $nativeBuild, '--config', 'Release', '--target', 'whisper-cli', '--parallel', '2')
# Resolve the pinned SDK from windows/global.json, then prohibit dependency drift.
Push-Location (Join-Path $root 'windows/VoiceInput.Windows')
try {
    $sdkVersion = (& dotnet --version).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Pinned .NET SDK could not be resolved.' }
    Invoke-Checked 'dotnet' @('restore', 'VoiceInput.Windows.csproj', '-r', 'win-x64', '--locked-mode',
        '-p:PublishSingleFile=true', '-p:SelfContained=true')
    Invoke-Checked 'dotnet' @('publish', 'VoiceInput.Windows.csproj', '--no-restore', '-c', 'Release',
        '-r', 'win-x64', '--self-contained', 'true', '-p:PublishSingleFile=true',
        '-p:IncludeNativeLibrariesForSelfExtract=true', '-p:PublishTrimmed=false', '-o', $package)
    $runtimeConfig = Get-Content 'bin/Release/net10.0-windows/win-x64/VoiceInput.runtimeconfig.json' -Raw | ConvertFrom-Json
    $runtimePack = @($runtimeConfig.runtimeOptions.includedFrameworks | Where-Object { $_.name -eq 'Microsoft.NETCore.App' })
    if ($runtimePack.Count -ne 1) { throw 'Cannot identify the exact published .NET runtime.' }
    $runtimeVersion = $runtimePack[0].version
    $desktopPack = @($runtimeConfig.runtimeOptions.includedFrameworks | Where-Object { $_.name -eq 'Microsoft.WindowsDesktop.App' })
    if ($desktopPack.Count -ne 1) { throw 'Cannot identify the exact published Windows desktop runtime.' }
    $desktopRuntimeVersion = $desktopPack[0].version
} finally { Pop-Location }
if (-not (Test-Path (Join-Path $package 'VoiceInput.exe'))) { throw 'Publish did not produce VoiceInput.exe.' }
$backend = Join-Path $package 'backend'
$models = Join-Path $package 'models'
$licenses = Join-Path $package 'licenses'
New-Item -ItemType Directory -Path $backend, $models, $licenses | Out-Null
Copy-Item (Join-Path $nativeBuild 'bin/Release/whisper-cli.exe') $backend
# Copy any generated DLLs beside the backend, should upstream ever require them.
Get-ChildItem $nativeBuild -Recurse -Filter '*.dll' | Where-Object { $_.Directory.Name -eq 'Release' } | Copy-Item -Destination $backend
$model = Join-Path $models 'ggml-small.bin'
Invoke-WebRequest 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin?download=true' -OutFile $model
if ((Get-Item $model).Length -ne $modelSize -or (Get-FileHash $model -Algorithm SHA256).Hash.ToLowerInvariant() -ne $modelHash) {
    throw 'ggml-small.bin size or SHA256 mismatch. Package will not be released.'
}
Copy-Item (Join-Path $src 'LICENSE') (Join-Path $licenses 'whisper.cpp-MIT.txt')
Invoke-WebRequest 'https://raw.githubusercontent.com/openai/whisper/v20240930/LICENSE' -OutFile (Join-Path $licenses 'OpenAI-Whisper-MIT.txt')
Invoke-WebRequest 'https://raw.githubusercontent.com/naudio/NAudio/v2.2.1/license.txt' -OutFile (Join-Path $licenses 'NAudio-MIT.txt')
Invoke-WebRequest "https://raw.githubusercontent.com/dotnet/runtime/v$runtimeVersion/LICENSE.TXT" -OutFile (Join-Path $licenses 'dotnet-MIT.txt')
Invoke-WebRequest "https://raw.githubusercontent.com/dotnet/runtime/v$runtimeVersion/THIRD-PARTY-NOTICES.TXT" -OutFile (Join-Path $licenses 'dotnet-THIRD-PARTY-NOTICES.txt')
foreach ($component in @('wpf', 'winforms')) {
    Invoke-WebRequest "https://raw.githubusercontent.com/dotnet/$component/v$desktopRuntimeVersion/LICENSE.TXT" -OutFile (Join-Path $licenses "dotnet-$component-MIT.txt")
    Invoke-WebRequest "https://raw.githubusercontent.com/dotnet/$component/v$desktopRuntimeVersion/THIRD-PARTY-NOTICES.TXT" -OutFile (Join-Path $licenses "dotnet-$component-THIRD-PARTY-NOTICES.txt")
}
if (Test-Path (Join-Path $root 'LICENSE')) { Copy-Item (Join-Path $root 'LICENSE') (Join-Path $licenses 'VoiceInput-LICENSE.txt') }
@"
VoiceInput Windows 11 x64 预览版（Windows 10 兼容性待验收）
ZIP 为可携带版。解压整个 ZIP 并运行 VoiceInput.exe，保留旁边的 backend/ 和 models/ 文件夹。
包内附带 .NET 运行时和多语言 Whisper small 模型，转写可离线运行。
CPU 基础指令集构建，无需 CUDA/GPU 或单独安装 Visual C++ 运行时。
未签名预览版：Windows SmartScreen 可能显示提示。
自动门禁：EXE 启动检查、真实 JFK WAV 转写、无效输入拒绝、ZIP 解压文件完整性。
尚未验收：真人麦克风录音、快捷键冲突、跨 Windows 应用文字注入。
CPU 基础指令集优先兼容性，性能须在您的 Windows 电脑上实测。
"@ | Set-Content (Join-Path $package 'WINDOWS-PREVIEW.txt') -Encoding utf8
@{ whisperTag = 'v1.7.6'; whisperCommit = $whisperCommit; model = 'ggml-small.bin';
   modelSize = $modelSize; modelSha256 = $modelHash; runtime = 'win-x64'; sdkVersion = $sdkVersion; runtimeVersion = $runtimeVersion; desktopRuntimeVersion = $desktopRuntimeVersion; native = 'CPU baseline, static CRT';
   sourceCommit = (& git rev-parse HEAD).Trim() } | ConvertTo-Json | Set-Content (Join-Path $package 'build-info.json') -Encoding utf8
$zip = Join-Path $out 'VoiceInput-windows-x64.zip'
Compress-Archive -Path $package -DestinationPath $zip -CompressionLevel Optimal
# Execute the package extracted from the exact release ZIP, under a Chinese/space path.
# Hash every member against the publish directory before accepting it.
$extract = Join-Path $work 'ZIP 验收'
Expand-Archive -Path $zip -DestinationPath $extract
$extractedPackage = Join-Path $extract (Split-Path $package -Leaf)
$originalFiles = @(Get-ChildItem $package -Recurse -File)
$extractedFiles = @(Get-ChildItem $extractedPackage -Recurse -File)
if ($originalFiles.Count -ne $extractedFiles.Count) { throw 'ZIP member count mismatch.' }
foreach ($file in $originalFiles) {
    $relative = [IO.Path]::GetRelativePath($package, $file.FullName)
    $extractedFile = Join-Path $extractedPackage $relative
    if (-not (Test-Path $extractedFile) -or (Get-FileHash $file.FullName).Hash -ne (Get-FileHash $extractedFile).Hash) {
        throw "ZIP integrity check failed: $relative"
    }
}
& (Join-Path $PSScriptRoot 'verify-windows.ps1') -PackageDirectory $extractedPackage -Fixture (Join-Path $src 'samples/jfk.wav')
if (-not $?) { throw 'Windows aggregate verification failed.' }
Copy-Item (Join-Path $extract 'verification') (Join-Path $out 'verification') -Recurse
((Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant() + '  VoiceInput-windows-x64.zip') |
    Set-Content (Join-Path $out 'VoiceInput-windows-x64.zip.sha256') -Encoding ascii
Write-Host "Verified Windows preview package: $zip"
