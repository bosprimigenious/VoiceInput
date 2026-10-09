using System.Text;

namespace VoiceInput.Windows;

internal static class DiagnosticLog
{
    private static readonly object Gate = new();
    public static void Write(string eventName, string? details = null)
    {
        // Callers supply state/error categories, never audio, prompts or transcripts.
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(AppSettings.DataDirectory);
                var path = Path.Combine(AppSettings.DataDirectory, "app.log");
                if (File.Exists(path) && new FileInfo(path).Length > 2 * 1024 * 1024)
                    File.Move(path, path + "." + Guid.NewGuid().ToString("N") + ".log");
                var safeDetails = (details ?? "").Replace('\r', ' ').Replace('\n', ' ');
                File.AppendAllText(path, $"{DateTimeOffset.UtcNow:O} {eventName} {safeDetails}\n", Encoding.UTF8);
            }
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }
}
