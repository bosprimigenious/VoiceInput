using System.Text.Json;
using System.Text.Json.Serialization;

namespace VoiceInput.Windows;

internal sealed class AppSettings
{
    public static readonly string[] Models = ["small", "medium", "large-v3-turbo"];
    public static string DataDirectory => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VoiceInput");
    private static string SettingsPath => Path.Combine(DataDirectory, "settings.json");
    public string Model { get; set; } = "small";
    public string ModelDirectory { get; set; } = Path.Combine(AppContext.BaseDirectory, "models");
    public string Prompt { get; set; } = "";
    public string Language { get; set; } = "zh";
    public bool SimplifiedChinese { get; set; } = true;
    [JsonIgnore]
    public string ModelPath => Path.Combine(ModelDirectory, $"ggml-{Model}.bin");
    [JsonIgnore]
    public string? RecoveryWarning { get; private set; }

    public static AppSettings Load(string? path = null)
    {
        path ??= SettingsPath;
        try
        {
            if (!File.Exists(path)) return new();
            if (new FileInfo(path).Length > 1024 * 1024) throw new JsonException("配置文件过大");
            var settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(path))
                ?? throw new JsonException("配置不能是 null");
            settings.Normalize();
            return settings;
        }
        catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException or ArgumentException or NotSupportedException)
        {
            var warning = "无法读取设置，已使用默认配置。";
            try
            {
                if (File.Exists(path))
                {
                    var backup = path + ".invalid-" + Guid.NewGuid().ToString("N") + ".json";
                    File.Copy(path, backup);
                    warning += $"原配置已备份至 {backup}。";
                }
            }
            catch (Exception backupError) when (backupError is IOException or UnauthorizedAccessException)
            {
                warning += "备份失败，原配置仍保留；保存新设置前请检查目录权限。";
            }
            DiagnosticLog.Write("settings.recovered", error.GetType().Name);
            return new AppSettings { RecoveryWarning = warning };
        }
    }

    private void Normalize()
    {
        if (!Models.Contains(Model)) Model = "small";
        ModelDirectory = string.IsNullOrWhiteSpace(ModelDirectory)
            ? Path.Combine(AppContext.BaseDirectory, "models") : Path.GetFullPath(ModelDirectory);
        Prompt ??= "";
        if (!new[] { "zh", "en", "auto" }.Contains(Language)) Language = "zh";
    }

    public void Save(string? path = null)
    {
        Normalize();
        path = Path.GetFullPath(path ?? SettingsPath);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllText(temporary, JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
            if (File.Exists(path)) File.Copy(path, path + ".previous-" + Guid.NewGuid().ToString("N") + ".json");
            File.Move(temporary, path, true);
            RecoveryWarning = null;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
