using System.Diagnostics;
using System.Text;

namespace VoiceInput.Windows;

internal static class WhisperService
{
    public static string Executable => Path.Combine(AppContext.BaseDirectory, "backend", "whisper-cli.exe");
    public static void CheckDependencies(AppSettings settings, string? executable = null)
    {
        executable ??= Executable;
        if (!File.Exists(executable)) throw new FileNotFoundException("缺少 backend\\whisper-cli.exe。请完整解压 Windows 发布 ZIP，不要单独复制 VoiceInput.exe。", executable);
        if (!File.Exists(settings.ModelPath)) throw new FileNotFoundException($"缺少模型：{settings.ModelPath}\n在设置中选择模型目录，或从 https://huggingface.co/ggerganov/whisper.cpp 下载 ggml-{settings.Model}.bin 放到 models 文件夹。模型文件较大，需等待下载完整。", settings.ModelPath);
    }

    public static async Task<string> TranscribeAsync(string wav, AppSettings settings, CancellationToken cancellation, string? language = null,
        string? executable = null, TimeSpan? timeoutLimit = null)
    {
        cancellation.ThrowIfCancellationRequested();
        if (!File.Exists(wav)) throw new FileNotFoundException("录音文件不存在。", wav);
        executable ??= Executable;
        CheckDependencies(settings, executable);
        language ??= settings.Language;
        var outputBase = Path.Combine(Path.GetTempPath(), "VoiceInput-" + Guid.NewGuid().ToString("N"));
        var info = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true, StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8, WorkingDirectory = Path.GetDirectoryName(executable)! };
        foreach (var argument in new[] { "-m", settings.ModelPath, "-f", wav, "-l", language, "-otxt", "-of", outputBase, "-nt" }) info.ArgumentList.Add(argument);
        if (!string.IsNullOrWhiteSpace(settings.Prompt)) { info.ArgumentList.Add("--prompt"); info.ArgumentList.Add(settings.Prompt); }
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(timeoutLimit ?? TimeSpan.FromMinutes(10));
        using var process = new Process { StartInfo = info };
        try
        {
            if (!process.Start()) throw new InvalidOperationException("无法启动本地转写进程。");
            DiagnosticLog.Write("transcription.start", $"model={settings.Model} pid={process.Id}");
            var stdout = process.StandardOutput.ReadToEndAsync(timeout.Token);
            var stderr = process.StandardError.ReadToEndAsync(timeout.Token);
            try
            {
                await process.WaitForExitAsync(timeout.Token);
                // Descendants may keep inherited pipes open after the parent exits.
                // Apply the same deadline to EOF, not only the parent lifetime.
                await Task.WhenAll(stdout, stderr).WaitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                try
                {
                    if (!process.HasExited) process.Kill(entireProcessTree: true);
                    await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(2));
                }
                catch (Exception stopError) when (stopError is InvalidOperationException or System.ComponentModel.Win32Exception or TimeoutException)
                { DiagnosticLog.Write("transcription.stop_failed", stopError.GetType().Name); }
                // Close our readers without waiting indefinitely for descendant EOF.
                process.StandardOutput.Dispose();
                process.StandardError.Dispose();
                _ = Task.WhenAll(stdout, stderr).ContinueWith(task => { _ = task.Exception; },
                    CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.Default);
                DiagnosticLog.Write("transcription.cancelled", cancellation.IsCancellationRequested ? "user" : "timeout");
                if (cancellation.IsCancellationRequested) throw;
                throw new TimeoutException("转写超过等待期限，已停止。可在设置中改用 small 模型。");
            }
            await stdout;
            var error = await stderr;
            DiagnosticLog.Write("transcription.exit", $"code={process.ExitCode}");
            if (process.ExitCode != 0) throw new InvalidOperationException($"本地转写失败（退出码 {process.ExitCode}）：\n{error[..Math.Min(error.Length, 2500)]}");
            if (!File.Exists(outputBase + ".txt")) throw new InvalidOperationException("转写进程没有生成文本文件。");
            var text = (await File.ReadAllTextAsync(outputBase + ".txt", Encoding.UTF8, cancellation)).Trim();
            text = System.Text.RegularExpressions.Regex.Replace(text, @"\[(?:BLANK_AUDIO|MUSIC|音乐|静音|无声)\]|\((?:music|音乐)\)|[♪♫]+", "", System.Text.RegularExpressions.RegexOptions.IgnoreCase).Trim();
            if (string.IsNullOrWhiteSpace(text)) throw new InvalidOperationException("没有识别到语音，请检查麦克风后重试。");
            return settings.SimplifiedChinese && language != "en" ? NativeMethods.ToSimplified(text) : text;
        }
        finally
        {
            try { if (File.Exists(outputBase + ".txt")) File.Delete(outputBase + ".txt"); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { DiagnosticLog.Write("transcription.cleanup_failed", error.GetType().Name); }
        }
    }
}
