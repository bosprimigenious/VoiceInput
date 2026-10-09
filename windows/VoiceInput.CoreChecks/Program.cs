using System.Diagnostics;
using System.Text.Json;
using NAudio.Wave;
using VoiceInput.Windows;

// This subprocess deliberately exercises the production process boundary. It is
// not an accuracy test; real model inference remains a separate Windows gate.
if (args is ["--hold-pipe", var pidPath])
{
    File.WriteAllText(pidPath, Environment.ProcessId.ToString());
    await Task.Delay(TimeSpan.FromSeconds(15));
    return 0;
}
if (args.Contains("-m"))
{
    string Arg(string key) => args[Array.IndexOf(args, key) + 1];
    var mode = File.ReadAllText(Arg("-m"));
    if (mode == "error") { Console.Error.WriteLine("fixture failure"); return 7; }
    if (mode == "wait") { File.WriteAllText(Arg("-m") + ".pid", Environment.ProcessId.ToString()); await Task.Delay(TimeSpan.FromMinutes(2)); return 0; }
    if (mode == "missing-output") return 0;
    if (mode == "flood")
    {
        await Task.WhenAll(Console.Out.WriteAsync(new string('o', 2 * 1024 * 1024)), Console.Error.WriteAsync(new string('e', 2 * 1024 * 1024)));
    }
    if (mode == "inherited-pipe")
    {
        var childInfo = new ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false };
        childInfo.ArgumentList.Add("--hold-pipe");
        childInfo.ArgumentList.Add(Arg("-m") + ".descendant.pid");
        using var descendant = Process.Start(childInfo)!;
    }
    File.WriteAllText(Arg("-of") + ".txt", mode == "empty" ? " [BLANK_AUDIO] ♪ " : "fixture speech");
    return 0;
}

var root = Path.Combine(Path.GetTempPath(), "VoiceInput checks 中文 " + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(root);
var passed = 0;
void Assert(bool condition, string description)
{
    if (!condition) throw new InvalidOperationException(description);
    Console.WriteLine("PASS " + description); passed++;
}
async Task Reject<T>(Func<Task> action, string description) where T : Exception
{
    try { await action(); }
    catch (T) { Assert(true, description); return; }
    throw new InvalidOperationException("Expected " + typeof(T).Name + ": " + description);
}

try
{
    var path = Path.Combine(root, "settings.json");
    File.WriteAllText(path, "{ invalid");
    var settings = AppSettings.Load(path);
    Assert(settings.Model == "small" && settings.RecoveryWarning != null, "malformed settings recover");
    Assert(File.ReadAllText(path) == "{ invalid" && Directory.GetFiles(root, "*.invalid-*.json").Length == 1, "malformed original preserved and backed up");
    settings.Save(path);
    Assert(Directory.GetFiles(root, "*.previous-*.json").Length == 1, "save snapshots previous config");
    settings.Prompt = "自然句子 中文"; settings.Save(path);
    Assert(AppSettings.Load(path).Prompt == settings.Prompt, "settings UTF8 roundtrip");
    Assert(!File.ReadAllText(path).Contains("ModelPath") && !File.ReadAllText(path).Contains("RecoveryWarning"), "derived fields excluded from config");
    File.WriteAllText(path, "{\"Model\":\"../invalid\",\"Language\":null,\"Prompt\":null,\"ModelDirectory\":null}");
    settings = AppSettings.Load(path);
    Assert(settings.Model == "small" && settings.Language == "zh" && settings.Prompt == "" && Path.IsPathFullyQualified(settings.ModelDirectory), "invalid settings normalized");
    File.WriteAllText(path, "null");
    Assert(AppSettings.Load(path).RecoveryWarning != null, "null JSON recovers with warning");

    foreach (var format in new[] { WaveFormat.CreateIeeeFloatWaveFormat(48000, 2), new WaveFormat(44100, 16, 1), new WaveFormat(16000, 16, 1), WaveFormat.CreateIeeeFloatWaveFormat(48000, 4) })
    {
        var source = Path.Combine(root, $"native-{format.SampleRate}-{format.Channels}.wav");
        using (var writer = new WaveFileWriter(source, format)) writer.Write(new byte[format.AverageBytesPerSecond], 0, format.AverageBytesPerSecond);
        var destination = source + ".16k.wav";
        AudioRecorder.ConvertToWhisperWave(source, destination);
        using (var reader = new WaveFileReader(destination))
        {
            Assert(reader.WaveFormat.SampleRate == 16000 && reader.WaveFormat.BitsPerSample == 16 && reader.WaveFormat.Channels == 1, $"audio {format.SampleRate}/{format.Channels} converted to 16k PCM16 mono");
            Assert(Math.Abs(reader.TotalTime.TotalSeconds - 1) < .01, "resampling retains duration");
        }
        using var exclusive = new FileStream(destination, FileMode.Open, FileAccess.Read, FileShare.None);
        Assert(exclusive.Length > 32000, "converted WAV writer released");
    }
    var stereoPath = Path.Combine(root, "opposite stereo.wav");
    using (var writer = new WaveFileWriter(stereoPath, WaveFormat.CreateIeeeFloatWaveFormat(48000, 2)))
    {
        var opposite = new float[48000 * 2];
        for (var i = 0; i < opposite.Length; i += 2) { opposite[i] = .5f; opposite[i + 1] = -.5f; }
        writer.WriteSamples(opposite, 0, opposite.Length);
    }
    AudioRecorder.ConvertToWhisperWave(stereoPath, stereoPath + ".mono.wav");
    using (var reader = new WaveFileReader(stereoPath + ".mono.wav"))
    {
        var bytes = new byte[reader.Length]; reader.ReadExactly(bytes);
        Assert(bytes.All(x => x == 0), "multichannel downmix averages opposing channels");
    }

    settings = new AppSettings { ModelDirectory = root, Language = "en", SimplifiedChinese = false };
    var model = settings.ModelPath;
    var wav = Path.Combine(root, "input 空格.wav"); File.WriteAllText(wav, "fixture");
    var executable = Environment.ProcessPath!;
    Assert(!Path.GetFileNameWithoutExtension(executable).Equals("dotnet", StringComparison.OrdinalIgnoreCase), "fixture uses built apphost");
    async Task<string> Run(string mode, CancellationToken token = default, TimeSpan? timeout = null)
    {
        File.WriteAllText(model, mode);
        return await WhisperService.TranscribeAsync(wav, settings, token, "en", executable, timeout);
    }
    Assert(await Run("success") == "fixture speech", "real subprocess output read under Chinese space path");
    await Reject<InvalidOperationException>(async () => { await Run("error"); }, "nonzero process exit rejected");
    await Reject<InvalidOperationException>(async () => { await Run("missing-output"); }, "missing process output rejected");
    await Reject<InvalidOperationException>(async () => { await Run("empty"); }, "silence-only output rejected");
    Assert(await Run("flood") == "fixture speech", "stdout and stderr flood drained without deadlock");
    var stopwatch = Stopwatch.StartNew();
    await Reject<TimeoutException>(async () => { await Run("wait", timeout: TimeSpan.FromSeconds(3)); }, "timeout terminates child");
    Assert(stopwatch.Elapsed < TimeSpan.FromSeconds(10), "timeout returns within bound");
    void AssertChildExited()
    {
        var pid = int.Parse(File.ReadAllText(model + ".pid"));
        var exited = false;
        try { using var child = Process.GetProcessById(pid); exited = child.HasExited; }
        catch (ArgumentException) { exited = true; }
        Assert(exited, "cancelled child is no longer running");
    }
    AssertChildExited();
    File.Delete(model + ".pid");
    using var cancelled = new CancellationTokenSource();
    var pending = Run("wait", cancelled.Token);
    var readyDeadline = Stopwatch.StartNew();
    while (!File.Exists(model + ".pid") && readyDeadline.Elapsed < TimeSpan.FromSeconds(5)) await Task.Delay(20);
    cancelled.Cancel();
    await Reject<OperationCanceledException>(async () => { await pending; }, "user cancellation terminates child");
    AssertChildExited();
    await Reject<FileNotFoundException>(async () => { await WhisperService.TranscribeAsync(Path.Combine(root, "missing.wav"), settings, default, "en", executable); }, "missing WAV rejected before launch");
    Console.WriteLine($"Existing core checks passed: {passed}");
    // A parent exiting does not close pipes inherited by its descendants. The
    // production timeout must cover output draining as well as parent lifetime.
    var descendantPidPath = model + ".descendant.pid";
    var inheritedPipe = Run("inherited-pipe", timeout: TimeSpan.FromSeconds(1));
    try
    {
        if (await Task.WhenAny(inheritedPipe, Task.Delay(TimeSpan.FromSeconds(4))) != inheritedPipe)
            throw new InvalidOperationException("FAIL inherited output pipe: production timeout=1s, task still pending after 4s");
        await Reject<TimeoutException>(async () => { await inheritedPipe; }, "inherited output pipe obeys production timeout");
    }
    finally
    {
        if (File.Exists(descendantPidPath))
        {
            try { using var descendant = Process.GetProcessById(int.Parse(File.ReadAllText(descendantPidPath))); descendant.Kill(); descendant.WaitForExit(3000); }
            catch (ArgumentException) { }
        }
        try { await inheritedPipe.WaitAsync(TimeSpan.FromSeconds(3)); } catch (Exception) { }
    }
    Console.WriteLine($"Core checks passed: {passed}");
    return 0;
}
catch (Exception error) { Console.Error.WriteLine(error); return 1; }

namespace VoiceInput.Windows
{
    // These checks use English. Chinese conversion requires the Windows native gate.
    internal static class NativeMethods
    {
        internal static string ToSimplified(string text) => throw new InvalidOperationException("Native conversion must not execute in core checks.");
    }
}
