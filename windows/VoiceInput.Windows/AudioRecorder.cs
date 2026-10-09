using System.IO;
using NAudio.CoreAudioApi;
using NAudio.Wave;
using NAudio.Wave.SampleProviders;

namespace VoiceInput.Windows;

internal sealed class AudioRecorder : IDisposable
{
    private readonly WasapiCapture input;
    private readonly WaveFileWriter writer;
    private readonly string nativePath;
    private readonly string outputPath;
    private readonly object gate = new();
    private readonly TaskCompletionSource completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private volatile bool disposed;
    private bool writerClosed;
    private int stopRequested, disposeRequested;
    private Exception? writeError;
    private readonly CancellationTokenSource conversionCancellation = new();
    public Task Completion => completion.Task;

    public AudioRecorder(string path)
    {
        outputPath = path;
        nativePath = path + ".native.wav";
        // Capture at the default endpoint's native format: many USB/Bluetooth devices
        // do not accept the 16 kHz PCM format required by whisper.cpp directly.
        input = new WasapiCapture();
        try { writer = new WaveFileWriter(nativePath, input.WaveFormat); }
        catch { input.Dispose(); throw; }
        input.DataAvailable += OnDataAvailable;
        input.RecordingStopped += OnRecordingStopped;
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs e)
    {
        lock (gate)
        {
            if (disposed || writerClosed || writeError != null) return;
            try { writer.Write(e.Buffer, 0, e.BytesRecorded); }
            catch (Exception error) { writeError = error; }
        }
        if (writeError != null)
        {
            try { input.StopRecording(); }
            catch (Exception error) { completion.TrySetException(error); }
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs e)
    {
        // NAudio posts this event to the constructing UI synchronization context.
        // Move the final conversion off that context before doing any file work.
        _ = Task.Run(() => FinalizeRecording(e.Exception));
    }

    private void FinalizeRecording(Exception? captureError)
    {
        var staging = outputPath + ".converting.wav";
        Exception? error;
        lock (gate)
        {
            if (disposed) return;
            error = captureError ?? writeError;
            try { CloseWriter(); }
            catch (Exception closeError) { error ??= closeError; }
        }
        try
        {
            if (error == null) ConvertToWhisperWave(nativePath, staging, conversionCancellation.Token);
            lock (gate)
            {
                if (disposed) return;
                if (error == null) File.Move(staging, outputPath);
                if (error != null) completion.TrySetException(error);
                else completion.TrySetResult();
            }
        }
        catch (Exception conversionError)
        {
            completion.TrySetException(conversionError);
        }
        finally
        {
            DeleteNativeFile();
            TryDelete(staging);
        }
    }

    internal static void ConvertToWhisperWave(string sourcePath, string destinationPath, CancellationToken cancellation = default)
    {
        using var reader = new WaveFileReader(sourcePath);
        ISampleProvider samples = new CancellableSampleProvider(reader.ToSampleProvider(), cancellation);
        if (samples.WaveFormat.Channels != 1) samples = new MonoSampleProvider(samples);
        if (samples.WaveFormat.SampleRate != 16000) samples = new WdlResamplingSampleProvider(samples, 16000);
        WaveFileWriter.CreateWaveFile16(destinationPath, samples);
    }

    private sealed class CancellableSampleProvider(ISampleProvider source, CancellationToken cancellation) : ISampleProvider
    {
        public WaveFormat WaveFormat => source.WaveFormat;
        public int Read(float[] buffer, int offset, int count)
        {
            cancellation.ThrowIfCancellationRequested();
            return source.Read(buffer, offset, count);
        }
    }

    private sealed class MonoSampleProvider(ISampleProvider source) : ISampleProvider
    {
        private readonly int channels = source.WaveFormat.Channels;
        private float[] scratch = [];
        public WaveFormat WaveFormat { get; } = WaveFormat.CreateIeeeFloatWaveFormat(source.WaveFormat.SampleRate, 1);
        public int Read(float[] buffer, int offset, int count)
        {
            var required = checked(count * channels);
            if (scratch.Length < required) scratch = new float[required];
            var read = source.Read(scratch, 0, required);
            var frames = read / channels;
            for (var frame = 0; frame < frames; frame++)
            {
                var sum = 0f;
                for (var channel = 0; channel < channels; channel++) sum += scratch[frame * channels + channel];
                buffer[offset + frame] = sum / channels;
            }
            return frames;
        }
    }

    public void Start()
    {
        try { input.StartRecording(); }
        catch (Exception error) { completion.TrySetException(error); throw; }
    }
    public Task StopAsync()
    {
        if (disposed) return completion.Task;
        if (Interlocked.Exchange(ref stopRequested, 1) == 0)
        {
            try { input.StopRecording(); }
            catch (Exception error) { completion.TrySetException(error); }
        }
        return completion.Task;
    }
    private void CloseWriter()
    {
        if (writerClosed) return;
        writerClosed = true;
        writer.Dispose();
    }
    private void DeleteNativeFile() => TryDelete(nativePath);
    private static void TryDelete(string path)
    {
        try { File.Delete(path); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
    public void Dispose()
    {
        if (Interlocked.Exchange(ref disposeRequested, 1) != 0) return;
        disposed = true;
        conversionCancellation.Cancel();
        completion.TrySetCanceled();
        // NAudio Dispose calls captureThread.Join() without a timeout. Request stop
        // immediately, but reclaim COM resources on a background worker so a broken
        // device cannot prevent the tray UI from closing. Callbacks see disposed.
        try { input.StopRecording(); }
        catch (Exception error) { DiagnosticLog.Write("recording.stop_failed", error.GetType().Name); }
        _ = Task.Run(() =>
        {
            try { input.Dispose(); }
            catch (Exception error) { DiagnosticLog.Write("recording.dispose_failed", error.GetType().Name); }
            finally
            {
                // Never make the UI wait for a writer/converter which holds gate.
                lock (gate)
                {
                    try { CloseWriter(); }
                    catch (Exception error) { DiagnosticLog.Write("recording.close_failed", error.GetType().Name); }
                    finally { DeleteNativeFile(); }
                }
            }
        });
    }
}
