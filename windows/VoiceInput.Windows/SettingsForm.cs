namespace VoiceInput.Windows;

internal sealed class SettingsForm : Form
{
    public SettingsForm(AppSettings settings)
    {
        Text = "VoiceInput 设置";
        Width = 640; Height = 440; StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog; MaximizeBox = false; MinimizeBox = false;
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(16), ColumnCount = 2, RowCount = 7 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110)); layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        var model = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
        model.Items.AddRange(AppSettings.Models); model.SelectedItem = settings.Model;
        var directory = new TextBox { Text = settings.ModelDirectory, Dock = DockStyle.Fill };
        var prompt = new TextBox { Text = settings.Prompt, Multiline = true, Height = 70, Dock = DockStyle.Fill };
        var simplified = new CheckBox { Text = "规范为简体中文", Checked = settings.SimplifiedChinese, AutoSize = true };
        var language = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
        language.Items.AddRange(new[] { "zh", "en", "auto" }); language.SelectedItem = settings.Language;
        var help = new LinkLabel { Text = "下载 ggml 模型（small / medium / large-v3-turbo）", AutoSize = true };
        help.LinkClicked += (_, _) => System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("https://huggingface.co/ggerganov/whisper.cpp/tree/main") { UseShellExecute = true });
        var save = new Button { Text = "保存", AutoSize = true };
        save.Click += (_, _) =>
        {
            try
            {
                var fullPath = Path.GetFullPath(directory.Text.Trim());
                var previous = (settings.Model, settings.ModelDirectory, settings.Prompt, settings.SimplifiedChinese, settings.Language);
                settings.Model = (string)model.SelectedItem!; settings.ModelDirectory = fullPath; settings.Prompt = prompt.Text; settings.SimplifiedChinese = simplified.Checked;
                settings.Language = (string)language.SelectedItem!;
                try { settings.Save(); }
                catch { (settings.Model, settings.ModelDirectory, settings.Prompt, settings.SimplifiedChinese, settings.Language) = previous; throw; }
                DialogResult = DialogResult.OK; Close();
            }
            catch (Exception e) { MessageBox.Show(this, e.Message, "保存失败", MessageBoxButtons.OK, MessageBoxIcon.Error); }
        };
        layout.Controls.Add(new Label { Text = "模型", AutoSize = true }, 0, 0); layout.Controls.Add(model, 1, 0);
        layout.Controls.Add(new Label { Text = "模型目录", AutoSize = true }, 0, 1); layout.Controls.Add(directory, 1, 1);
        layout.Controls.Add(new Label { Text = "自然句提示词", AutoSize = true }, 0, 2); layout.Controls.Add(prompt, 1, 2);
        layout.Controls.Add(simplified, 1, 3); layout.Controls.Add(help, 1, 4); layout.Controls.Add(save, 1, 5);
        layout.Controls.Add(new Label { Text = "语言 zh/en/auto", AutoSize = true }, 0, 6); layout.Controls.Add(language, 1, 6);
        layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 35)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 40)); layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 90));
        Controls.Add(layout); AcceptButton = save;
    }
}
