using System.IO;
namespace VoiceInput.Windows;

internal sealed class TrayForm : Form
{
    private enum Mode { Idle, Recording, Stopping, Transcribing }
    private readonly AppSettings settings;
    private readonly NotifyIcon tray;
    private readonly ToolStripMenuItem status = new("就绪 · Ctrl+I 开始录音") { Enabled = false };
    private readonly CancellationTokenSource lifetime = new();
    private readonly System.Windows.Forms.Timer recordingLimit = new() { Interval = 5 * 60 * 1000 };
    private Mode mode;
    private AudioRecorder? recorder;
    private string? wav;
    private string lastText = "";
    private InputTargetTracker? target;
    private bool exiting, hotkeyRegistered;
    private Task? activeOperation;
    private bool resourcesReleased;

    public TrayForm(AppSettings settings)
    {
        this.settings = settings;
        Text = "VoiceInput"; ShowInTaskbar = false; WindowState = FormWindowState.Minimized;
        var menu = new ContextMenuStrip(); menu.Items.Add(status); menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("设置 / 模型下载", null, (_, _) =>
        {
            if (mode != Mode.Idle) { Notify("请先等待录音或转写结束。"); return; }
            using var form = new SettingsForm(settings); form.ShowDialog();
        });
        menu.Items.Add("查看 / 复制最近文本", null, (_, _) => ShowResult());
        menu.Items.Add("退出", null, async (_, _) => await ExitAsync());
        tray = new NotifyIcon { Icon = SystemIcons.Application, Text = "VoiceInput · Ctrl+I 开始录音", ContextMenuStrip = menu, Visible = true };
        tray.DoubleClick += (_, _) => ShowResult();
        recordingLimit.Tick += (_, _) => { recordingLimit.Stop(); if (mode == Mode.Recording) activeOperation = ToggleAsync(); };
    }
    protected override void OnShown(EventArgs e)
    {
        base.OnShown(e); Hide();
        hotkeyRegistered = NativeMethods.RegisterHotKey(Handle, 1, 0x4002, 0x49);
        if (!hotkeyRegistered) { MessageBox.Show("无法注册 Ctrl+I：快捷键可能已被其他程序占用。请关闭冲突程序后重新启动 VoiceInput。", "VoiceInput", MessageBoxButtons.OK, MessageBoxIcon.Error); Close(); return; }
        try { WhisperService.CheckDependencies(settings); Notify("Ctrl+I 开始 / 停止录音；右键托盘图标可设置模型。"); }
        catch (Exception error) { MessageBox.Show(error.Message, "首次启动：准备模型", MessageBoxButtons.OK, MessageBoxIcon.Information); }
    }
    protected override void WndProc(ref Message message)
    {
        if (message.Msg == 0x0312 && message.WParam == (IntPtr)1)
        {
            if (Application.OpenForms.Count > 1) return;
            if (mode is Mode.Idle or Mode.Recording) activeOperation = ToggleAsync();
            return;
        }
        base.WndProc(ref message);
    }
    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!exiting && e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            _ = ExitAsync();
        }
        base.OnFormClosing(e);
    }
    private void SetMode(Mode value)
    {
        mode = value;
        if (exiting || resourcesReleased || IsDisposed) return;
        var text = value switch { Mode.Recording => "录音中 · Ctrl+I 停止", Mode.Stopping => "正在停止录音…", Mode.Transcribing => "正在本地转写…", _ => "就绪 · Ctrl+I 开始录音" };
        status.Text = text; tray.Text = "VoiceInput · " + text;
        tray.Icon = value == Mode.Recording ? SystemIcons.Warning : SystemIcons.Application;
    }
    private async Task ToggleAsync()
    {
        if (exiting || mode is Mode.Stopping or Mode.Transcribing) return;
        try
        {
            if (mode == Mode.Idle)
            {
                WhisperService.CheckDependencies(settings);
                target = InputTargetTracker.Capture();
                wav = Path.Combine(Path.GetTempPath(), "VoiceInput-" + Guid.NewGuid().ToString("N") + ".wav");
                recorder = new AudioRecorder(wav);
                recorder.Start(); SetMode(Mode.Recording); recordingLimit.Start();
                DiagnosticLog.Write("recording_started");
                _ = ObserveRecorderAsync(recorder);
                Notify("正在录音，再按 Ctrl+I 停止（最长 5 分钟）。");
                return;
            }
            SetMode(Mode.Stopping); recordingLimit.Stop();
            await recorder!.StopAsync().WaitAsync(TimeSpan.FromSeconds(5));
            if (exiting) return;
            recorder.Dispose(); recorder = null;
            DiagnosticLog.Write("recording_stopped");
            SetMode(Mode.Transcribing);
            lastText = await WhisperService.TranscribeAsync(wav!, settings, lifetime.Token);
            if (exiting) return;
            DiagnosticLog.Write("transcription_completed");
            // Preserve the result in memory before persistence/clipboard operations.
            // A full disk must not prevent copying and pasting an otherwise valid result.
            try
            {
                Directory.CreateDirectory(AppSettings.DataDirectory);
                File.WriteAllText(Path.Combine(AppSettings.DataDirectory, "last-transcript.txt"), lastText);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                DiagnosticLog.Write("transcript_save_failed", error.GetType().Name);
                Notify("最近文本保存失败；本次文本仍可从托盘查看 / 复制。");
            }
            Clipboard.SetText(lastText);
            var pasted = target != null && await target.PasteAsync(lifetime.Token);
            if (exiting || resourcesReleased || IsDisposed) return;
            DiagnosticLog.Write(pasted ? "paste_sent" : "paste_skipped");
            Notify(pasted ? "已发送粘贴指令，文本也已保留在剪贴板。" : "未自动粘贴：原窗口或输入焦点已变化，或系统阻止输入。文本已保留，可手动 Ctrl+V。");
        }
        catch (OperationCanceledException) when (exiting) { }
        catch (Exception error) { DiagnosticLog.Write("operation_failed", error.GetType().Name); if (!exiting && !resourcesReleased && !IsDisposed) MessageBox.Show(error.Message + (lastText.Length > 0 ? "\n最近文本可从托盘菜单查看 / 复制。" : ""), "VoiceInput", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        finally
        {
            if (mode != Mode.Recording) { CleanupRecording(); if (!exiting) SetMode(Mode.Idle); }
        }
    }
    private async Task ObserveRecorderAsync(AudioRecorder active)
    {
        try
        {
            await active.Completion;
            if (mode == Mode.Recording && recorder == active && !exiting)
            {
                CleanupRecording(); SetMode(Mode.Idle); Notify("录音设备意外停止，请检查麦克风后重试。");
            }
        }
        catch (Exception e)
        {
            if (mode == Mode.Recording && recorder == active && !exiting) { CleanupRecording(); SetMode(Mode.Idle); MessageBox.Show(e.Message, "麦克风录音失败"); }
        }
    }
    private void CleanupRecording()
    {
        if (!resourcesReleased) recordingLimit.Stop();
        target?.Dispose(); target = null;
        var activeRecorder = recorder; recorder = null;
        try { activeRecorder?.Dispose(); } catch (Exception error) { DiagnosticLog.Write("recorder_cleanup_failed", error.GetType().Name); }
        if (wav != null)
        {
            try { File.Delete(wav); } catch (IOException) { } catch (UnauthorizedAccessException) { }
            wav = null;
        }
    }
    private void Notify(string text) { if (exiting || resourcesReleased || IsDisposed) return; tray.BalloonTipTitle = "VoiceInput"; tray.BalloonTipText = text; tray.ShowBalloonTip(4000); }
    private void ShowResult()
    {
        if (string.IsNullOrEmpty(lastText)) { Notify("本次运行还没有转写文本。"); return; }
        using var form = new Form { Text = "最近转写文本（失败时可手动复制）", Width = 650, Height = 400, StartPosition = FormStartPosition.CenterScreen };
        var text = new TextBox { Text = lastText, Multiline = true, ReadOnly = true, Dock = DockStyle.Fill, ScrollBars = ScrollBars.Vertical };
        var copy = new Button { Text = "复制到剪贴板", Dock = DockStyle.Bottom, Height = 40 };
        copy.Click += (_, _) => { try { Clipboard.SetText(lastText); } catch (Exception e) { MessageBox.Show(e.Message, "复制失败"); } };
        form.Controls.Add(text); form.Controls.Add(copy); form.ShowDialog();
    }
    private async Task ExitAsync()
    {
        if (exiting) return;
        exiting = true; lifetime.Cancel(); recordingLimit.Stop();
        DiagnosticLog.Write("exit_requested");
        if (recorder != null)
        {
            try { await recorder.StopAsync().WaitAsync(TimeSpan.FromSeconds(3)); } catch (Exception) { }
        }
        if (activeOperation != null) { try { await activeOperation.WaitAsync(TimeSpan.FromSeconds(8)); } catch (Exception) { } }
        CleanupRecording(); if (!IsDisposed) Close();
    }
    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        ReleaseResources();
        base.OnFormClosed(e);
    }
    private void ReleaseResources()
    {
        if (resourcesReleased) return;
        resourcesReleased = true;
        exiting = true; lifetime.Cancel();
        if (hotkeyRegistered) NativeMethods.UnregisterHotKey(Handle, 1);
        CleanupRecording(); recordingLimit.Dispose(); tray.Visible = false; tray.Dispose();
    }
    protected override void Dispose(bool disposing)
    {
        if (disposing) ReleaseResources();
        base.Dispose(disposing);
    }
}
