using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;

namespace TenantInstaller.Ui;

public partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
    }

    private void UseLocalDatabaseChanged(object sender, RoutedEventArgs e)
    {
        var isLocal = UseLocalDatabaseCheckBox.IsChecked == true;
        DatabaseHostTextBox.IsEnabled = !isLocal;
    }

    private void EnableSmtpChanged(object sender, RoutedEventArgs e)
    {
        var enabled = EnableSmtpCheckBox.IsChecked == true;
        SmtpHostTextBox.IsEnabled = enabled;
        SmtpPortTextBox.IsEnabled = enabled;
        SmtpUserTextBox.IsEnabled = enabled;
        SmtpPasswordBox.IsEnabled = enabled;
        SmtpEncryptionComboBox.IsEnabled = enabled;
        MailFromAddressTextBox.IsEnabled = enabled;
    }

    private void PreviewConfigClicked(object sender, RoutedEventArgs e)
    {
        var state = BuildState();
        var errors = state.Validate();

        if (errors.Length > 0)
        {
            MessageBox.Show(string.Join(Environment.NewLine, errors), "Validierung", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var json = JsonSerializer.Serialize(state, new JsonSerializerOptions { WriteIndented = true });
        LogTextBox.Text = json;
        StatusTextBlock.Text = "Konfiguration ist valide.";
    }

    private async void StartInstallClicked(object sender, RoutedEventArgs e)
    {
        var state = BuildState();
        var errors = state.Validate();

        if (errors.Length > 0)
        {
            MessageBox.Show(string.Join(Environment.NewLine, errors), "Validierung", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var installScript = FindInstallScript();

        if (installScript is null)
        {
            MessageBox.Show("windows\\scripts\\install.ps1 wurde relativ zur Anwendung nicht gefunden.", "Fehlendes Skript", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        var configPath = Path.Combine(Path.GetTempPath(), $"tenant-installer-config-{Guid.NewGuid():N}.json");
        var json = JsonSerializer.Serialize(state, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(configPath, json, Encoding.UTF8);

        var arguments = new StringBuilder();
        arguments.Append("-NoProfile -ExecutionPolicy Bypass -File ");
        arguments.Append('"').Append(installScript).Append('"');
        arguments.Append(" -ConfigPath ");
        arguments.Append('"').Append(configPath).Append('"');
        arguments.Append(" -PhpRuntimeMode ");
        arguments.Append(state.PhpRuntimeMode);

        if (DryRunCheckBox.IsChecked == true)
        {
            arguments.Append(" -DryRun");
        }

        var gitHubToken = GitHubTokenBox.Password.Trim();

        if (!string.IsNullOrWhiteSpace(gitHubToken))
        {
            arguments.Append(" -GitHubToken ");
            arguments.Append('"').Append(gitHubToken.Replace("\"", "\\\"")).Append('"');
        }

        StatusTextBlock.Text = "Installationsskript laeuft...";
        LogTextBox.Clear();

        try
        {
            await RunProcessAsync("powershell.exe", arguments.ToString());
            StatusTextBlock.Text = "Installationsskript abgeschlossen.";
        }
        catch (Exception ex)
        {
            StatusTextBlock.Text = "Installationsskript fehlgeschlagen.";
            MessageBox.Show(ex.Message, "Installationsfehler", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            TryDeleteTempFile(configPath);
        }
    }

    private WizardState BuildState()
    {
        var smtpMode = (SmtpEncryptionComboBox.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "tls";
        var runtimeMode = (PhpRuntimeModeComboBox.SelectedItem as ComboBoxItem)?.Content?.ToString() ?? "ScheduledTask";

        return new WizardState
        {
            PrimaryDomain = PrimaryDomainTextBox.Text.Trim(),
            UseSsl = UseSslCheckBox.IsChecked == true,
            AdminEmail = AdminEmailTextBox.Text.Trim(),
            AdminPassword = AdminPasswordBox.Password,
            UseLocalDatabase = UseLocalDatabaseCheckBox.IsChecked == true,
            DatabaseHost = DatabaseHostTextBox.Text.Trim(),
            DatabasePort = DatabasePortTextBox.Text.Trim(),
            DatabaseName = DatabaseNameTextBox.Text.Trim(),
            DatabaseUser = DatabaseUserTextBox.Text.Trim(),
            DatabasePassword = DatabasePasswordBox.Password,
            EnableSmtp = EnableSmtpCheckBox.IsChecked == true,
            SmtpHost = SmtpHostTextBox.Text.Trim(),
            SmtpPort = SmtpPortTextBox.Text.Trim(),
            SmtpUser = SmtpUserTextBox.Text.Trim(),
            SmtpPassword = SmtpPasswordBox.Password,
            SmtpEncryption = smtpMode,
            MailFromAddress = MailFromAddressTextBox.Text.Trim(),
            TenantId = TenantIdTextBox.Text.Trim(),
            LicenseKeys = LicenseKeysTextBox.Text.Trim(),
            PhpRuntimeMode = runtimeMode
        };
    }

    private string? FindInstallScript()
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);

        while (current is not null)
        {
            var candidate = Path.Combine(current.FullName, "windows", "scripts", "install.ps1");

            if (File.Exists(candidate))
            {
                return candidate;
            }

            current = current.Parent;
        }

        return null;
    }

    private async Task RunProcessAsync(string fileName, string arguments)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        var output = new StringBuilder();

        process.OutputDataReceived += (_, args) =>
        {
            if (args.Data is null)
            {
                return;
            }

            Dispatcher.Invoke(() =>
            {
                output.AppendLine(args.Data);
                LogTextBox.Text = output.ToString();
                LogTextBox.ScrollToEnd();
            });
        };

        process.ErrorDataReceived += (_, args) =>
        {
            if (args.Data is null)
            {
                return;
            }

            Dispatcher.Invoke(() =>
            {
                output.AppendLine(args.Data);
                LogTextBox.Text = output.ToString();
                LogTextBox.ScrollToEnd();
            });
        };

        if (!process.Start())
        {
            throw new InvalidOperationException("Der PowerShell-Prozess konnte nicht gestartet werden.");
        }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        await process.WaitForExitAsync();

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException($"Das Installationsskript ist mit Exit-Code {process.ExitCode} beendet worden.");
        }
    }

    private static void TryDeleteTempFile(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
        }
    }
}
