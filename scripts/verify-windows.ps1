param([Parameter(Mandatory)][string]$PackageDirectory, [Parameter(Mandatory)][string]$Fixture)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $IsWindows) { throw 'Verification must execute the real package on Windows.' }
$package = (Resolve-Path $PackageDirectory).Path
$fixturePath = (Resolve-Path $Fixture).Path
$exe = Join-Path $package 'VoiceInput.exe'
foreach ($relative in @('VoiceInput.exe', 'backend/whisper-cli.exe', 'models/ggml-small.bin', 'licenses/whisper.cpp-MIT.txt', 'licenses/OpenAI-Whisper-MIT.txt')) {
    if (-not (Test-Path (Join-Path $package $relative))) { throw "Missing package file: $relative" }
}
$evidence = Join-Path (Split-Path $package -Parent) 'verification'
New-Item -ItemType Directory -Path $evidence -ErrorAction Stop | Out-Null
function Run-App([string]$Name, [string[]]$Arguments, [int]$TimeoutSeconds) {
    $start = [Diagnostics.ProcessStartInfo]::new($exe)
    $start.UseShellExecute = $false
    $start.WorkingDirectory = $package
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    # Drain both pipes asynchronously so a verbose backend cannot block on full buffers.
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        $process.WaitForExit()
        $stdoutTask.GetAwaiter().GetResult() | Set-Content (Join-Path $evidence "$Name.stdout.txt") -Encoding utf8
        $stderrTask.GetAwaiter().GetResult() | Set-Content (Join-Path $evidence "$Name.stderr.txt") -Encoding utf8
        throw "App verification timed out: $($Arguments -join ' ')"
    }
    $exitCode = $process.ExitCode
    $stdoutTask.GetAwaiter().GetResult() | Set-Content (Join-Path $evidence "$Name.stdout.txt") -Encoding utf8
    $stderrTask.GetAwaiter().GetResult() | Set-Content (Join-Path $evidence "$Name.stderr.txt") -Encoding utf8
    @{ arguments = $Arguments; exitCode = $exitCode } | ConvertTo-Json |
        Set-Content (Join-Path $evidence "$Name.result.json") -Encoding utf8
    Write-Host "$Name exit code: $exitCode"
    if ($exitCode -ne 0) { Get-Content (Join-Path $evidence "$Name.stderr.txt") | Write-Host }
    $process.Dispose()
    return $exitCode
}
if ((Run-App 'smoke' @('--smoke-test') 60) -ne 0) { throw 'VoiceInput.exe smoke test failed.' }
$transcriptPath = Join-Path $evidence 'jfk-transcription.txt'
if ((Run-App 'jfk' @('--verify-transcription', $fixturePath, $transcriptPath) 600) -ne 0) { throw 'Real JFK transcription failed.' }
if (-not (Test-Path $transcriptPath)) { throw 'App produced no transcript.' }
$transcript = Get-Content $transcriptPath -Raw
Write-Host "JFK transcript: $transcript"
if ($transcript -notmatch '(?i)ask not what your country can do for you' -or $transcript -notmatch '(?i)what you can do for your country') {
    throw 'JFK transcription does not contain the expected speech.'
}
# Negative control: invalid input must fail, rather than return a canned successful transcript.
$badOutput = Join-Path $evidence 'invalid-transcription.txt'
if ((Run-App 'missing-audio' @('--verify-transcription', (Join-Path $evidence 'missing.wav'), $badOutput) 60) -eq 0) { throw 'Invalid audio incorrectly returned success.' }
if (Test-Path $badOutput) { throw 'Missing audio produced a transcript file.' }
$badAudio = Join-Path $evidence 'invalid.wav'
[IO.File]::WriteAllText($badAudio, 'This is deliberately not a WAV file.')
if ((Run-App 'malformed-audio' @('--verify-transcription', $badAudio, $badOutput) 60) -eq 0) { throw 'Malformed audio incorrectly returned success.' }
if (Test-Path $badOutput) { throw 'Malformed audio produced a transcript file.' }
@{ smoke = 'passed'; realTranscription = 'passed'; invalidAudio = 'passed';
   humanMicrophone = 'not tested'; textInjection = 'not tested'; timestampUtc = [DateTime]::UtcNow.ToString('o') } |
    ConvertTo-Json | Set-Content (Join-Path $evidence 'verification.json') -Encoding utf8
Write-Host 'Automated Windows package gates passed. Human microphone and text injection acceptance remains pending.'
