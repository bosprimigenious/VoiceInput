using System.Collections.Concurrent;
using System.Windows.Automation;

namespace VoiceInput.Windows;

/// <summary>
/// Records the actual UI Automation input element, including browser fields which share
/// an HWND. Any uncertain identity or change within the original window disables paste.
/// UIA calls and event registration/removal run on the same dedicated MTA thread.
/// </summary>
internal sealed class InputTargetTracker : IDisposable
{
    private readonly NativeMethods.InputTarget target;
    private readonly BlockingCollection<Action> work = new();
    private readonly TaskCompletionSource<bool> initialized = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int[]? runtimeId;
    private int elementProcess;
    private int invalid, disposed, pasteStarted;
    private bool IsValid => Volatile.Read(ref invalid) == 0 && Volatile.Read(ref disposed) == 0;

    private InputTargetTracker(NativeMethods.InputTarget target)
    {
        this.target = target;
        var thread = new Thread(Run) { IsBackground = true, Name = "VoiceInput input focus tracking" };
        thread.SetApartmentState(ApartmentState.MTA);
        thread.Start();
    }

    internal static InputTargetTracker Capture()
    {
        var tracker = new InputTargetTracker(NativeMethods.CaptureTarget());
        // A hung accessibility provider must not hold the recording UI indefinitely.
        if (!tracker.initialized.Task.Wait(TimeSpan.FromSeconds(1))) tracker.Invalidate();
        return tracker;
    }

    private void Run()
    {
        AutomationFocusChangedEventHandler handler = OnFocusChanged;
        var subscribed = false;
        try
        {
            if (!NativeMethods.IsOriginalWindow(target)) { Invalidate(); return; }
            var element = AutomationElement.FocusedElement;
            if (element == null || !IsEditable(element)) { Invalidate(); return; }
            runtimeId = element.GetRuntimeId();
            elementProcess = element.Current.ProcessId;
            if (runtimeId == null || runtimeId.Length == 0 || !BelongsToWindow(element)) { Invalidate(); return; }
            Automation.AddAutomationFocusChangedEventHandler(handler);
            subscribed = true;
            if (!MatchesCurrentElement()) Invalidate();
            initialized.TrySetResult(IsValid);
            while (Volatile.Read(ref disposed) == 0)
            {
                if (work.TryTake(out var action, 100)) action();
                // Supplement focus events: providers may omit an event, particularly in browsers.
                if (IsValid && NativeMethods.GetForegroundWindow() == target.Window && !MatchesCurrentElement()) Invalidate();
                if (work.IsCompleted) break;
            }
        }
        catch (Exception error)
        {
            Invalidate();
            System.Diagnostics.Debug.WriteLine(error);
        }
        finally
        {
            initialized.TrySetResult(false);
            Invalidate();
            if (subscribed)
            {
                try { Automation.RemoveAutomationFocusChangedEventHandler(handler); }
                catch (Exception error) { System.Diagnostics.Debug.WriteLine(error); }
            }
            while (work.TryTake(out var action)) action();
        }
    }

    private static bool IsEditable(AutomationElement element)
    {
        var info = element.Current;
        if (!info.IsEnabled || !info.IsKeyboardFocusable || !info.HasKeyboardFocus || info.IsPassword) return false;
        if (element.TryGetCurrentPattern(ValuePattern.Pattern, out var value)) return !((ValuePattern)value).Current.IsReadOnly;
        // Rich edit and browser contenteditable providers may expose TextPattern only.
        if ((info.ControlType != ControlType.Edit && info.ControlType != ControlType.Document)
            || !element.TryGetCurrentPattern(TextPattern.Pattern, out var text)) return false;
        return ((TextPattern)text).DocumentRange.GetAttributeValue(TextPattern.IsReadOnlyAttribute) is false;
    }

    private bool BelongsToWindow(AutomationElement element)
    {
        // Browser renderer processes can differ from the top-level HWND process. Verify
        // ancestry instead of assuming process equality for those UIA elements.
        for (var depth = 0; element != null && depth < 128; depth++)
        {
            if (element.Current.NativeWindowHandle == unchecked((int)target.Window.ToInt64())) return true;
            element = TreeWalker.RawViewWalker.GetParent(element);
        }
        return false;
    }

    private bool MatchesCurrentElement()
    {
        if (!IsValid || runtimeId == null || !NativeMethods.IsOriginalWindow(target)
            || NativeMethods.GetForegroundWindow() != target.Window || NativeMethods.FocusOf(target.Window) != target.Focus) return false;
        var focused = AutomationElement.FocusedElement;
        return focused != null && focused.Current.ProcessId == elementProcess
            && runtimeId.SequenceEqual(focused.GetRuntimeId()) && IsEditable(focused) && BelongsToWindow(focused);
    }

    private void OnFocusChanged(object sender, AutomationFocusChangedEventArgs args)
    {
        if (!IsValid) return;
        try
        {
            // Other applications are allowed to take focus. Restoring the original window
            // still requires its original element to be focused before any input is sent.
            if (NativeMethods.GetForegroundWindow() != target.Window) return;
            if (sender is not AutomationElement element || runtimeId == null
                || element.Current.ProcessId != elementProcess
                || !runtimeId.SequenceEqual(element.GetRuntimeId())) Invalidate();
        }
        catch (Exception error) { Invalidate(); System.Diagnostics.Debug.WriteLine(error); }
    }

    internal async Task<bool> PasteAsync(CancellationToken cancellation)
    {
        if (Interlocked.Exchange(ref pasteStarted, 1) != 0 || !IsValid) return false;
        using var attempt = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        try
        {
            if (!await NativeMethods.RestoreTargetAsync(target, attempt.Token) || !IsValid) return false;
            var result = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            if (!work.TryAdd(() =>
                {
                    try
                    {
                        result.TrySetResult(IsValid && NativeMethods.SendPaste(target, MatchesCurrentElement, attempt.Token));
                    }
                    catch (OperationCanceledException) { result.TrySetCanceled(); }
                    catch (Exception error) { Invalidate(); System.Diagnostics.Debug.WriteLine(error); result.TrySetResult(false); }
                })) return false;
            return await result.Task.WaitAsync(TimeSpan.FromSeconds(1), cancellation);
        }
        catch (OperationCanceledException) { Invalidate(); throw; }
        catch (Exception error) { Invalidate(); System.Diagnostics.Debug.WriteLine(error); return false; }
        finally { attempt.Cancel(); }
    }

    private void Invalidate() => Interlocked.Exchange(ref invalid, 1);

    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposed, 1) != 0) return;
        Invalidate();
        work.CompleteAdding();
        // The worker's finally removes the hook, including if initialization finishes
        // after disposal. Do not block the UI waiting for a broken external provider.
    }
}
