namespace VoiceInput.Windows;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        if (args.Length > 0)
        {
            Console.OutputEncoding = System.Text.Encoding.UTF8;
            try
            {
                var settings = new AppSettings();
                if (args is ["--smoke-test"])
                {
                    WhisperService.CheckDependencies(settings);
                    using var form = new TrayForm(settings);
                    _ = form.Handle;
                    using var devices = new NAudio.CoreAudioApi.MMDeviceEnumerator();
                    var endpoints = devices.EnumerateAudioEndPoints(NAudio.CoreAudioApi.DataFlow.Capture, NAudio.CoreAudioApi.DeviceState.Active);
                    _ = endpoints.Count;
                    _ = typeof(System.Windows.Automation.AutomationElement).Assembly.FullName;
                    foreach (var sample in new[] { ("語音輸入", "语音输入"), ("", ""), ("VoiceInput 語音", "VoiceInput 语音") })
                    {
                        var converted = NativeMethods.ToSimplified(sample.Item1);
                        if (converted != sample.Item2) throw new InvalidOperationException($"Chinese conversion failed: length={converted.Length}, UTF16={string.Join(",", converted.Select(c => ((int)c).ToString("X4")))}");
                    }
                    return 0;
                }
                if (args is ["--verify-transcription", var wav, var output])
                {
                    var text = WhisperService.TranscribeAsync(Path.GetFullPath(wav), settings, CancellationToken.None, "en").GetAwaiter().GetResult();
                    File.WriteAllText(Path.GetFullPath(output), text); return 0;
                }
                throw new ArgumentException("Usage: VoiceInput.exe [--smoke-test | --verify-transcription <wav> <output.txt>]");
            }
            catch (Exception e) { Console.Error.WriteLine(e); return 1; }
        }
        using var singleInstance = new Mutex(true, "Local\\VoiceInput.Windows", out var created);
        if (!created) { MessageBox.Show("VoiceInput 已经运行，请查看系统托盘。", "VoiceInput"); return 0; }
        try
        {
            var settings = AppSettings.Load();
            if (settings.RecoveryWarning != null) MessageBox.Show(settings.RecoveryWarning, "设置恢复", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            DiagnosticLog.Write("app.start");
            Application.Run(new TrayForm(settings));
            DiagnosticLog.Write("app.stop");
            return 0;
        }
        catch (Exception e) { MessageBox.Show(e.Message, "VoiceInput 启动失败", MessageBoxButtons.OK, MessageBoxIcon.Error); return 1; }
        finally { singleInstance.ReleaseMutex(); }
    }
}
