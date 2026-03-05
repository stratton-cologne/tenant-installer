using System.Diagnostics;
using System.IO;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;

namespace TenantInstaller.Ui;

public partial class MainWindow : Window
{
    private bool _isBusy;

    public MainWindow()
    {
        InitializeComponent();
        UseSslChanged(this, new RoutedEventArgs());
        UseLocalDatabaseChanged(this, new RoutedEventArgs());
        EnableSmtpChanged(this, new RoutedEventArgs());
        SetBusy(false);
    }

    private void UseSslChanged(object sender, RoutedEventArgs e)
    {
        var useSsl = UseSslCheckBox.IsChecked == true;
        SslCertificatePathTextBox.IsEnabled = useSsl;
        SslCertificateKeyPathTextBox.IsEnabled = useSsl;
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
        if (_isBusy)
        {
            return;
        }

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

    private async void TestDatabaseClicked(object sender, RoutedEventArgs e)
    {
        if (_isBusy)
        {
            return;
        }

        var state = BuildState();
        var errors = state.Validate();

        if (errors.Length > 0)
        {
            MessageBox.Show(string.Join(Environment.NewLine, errors), "Validierung", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var host = state.UseLocalDatabase ? "127.0.0.1" : state.DatabaseHost.Trim();

        if (!int.TryParse(state.DatabasePort, out var port))
        {
            MessageBox.Show("DB Port ist ungueltig.", "DB-Test", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        SetBusy(true);
        StatusTextBlock.Text = $"Teste DB-Verbindung zu {host}:{port} ...";

        try
        {
            var reachable = await TestTcpConnectivityAsync(host, port, 5000);

            if (reachable)
            {
                StatusTextBlock.Text = $"DB-Verbindung erreichbar: {host}:{port}";
                LogTextBox.Text = $"[INFO] DB-Verbindung erfolgreich getestet: {host}:{port}";
                return;
            }

            StatusTextBlock.Text = $"DB-Verbindung nicht erreichbar: {host}:{port}";
            LogTextBox.Text = $"[WARN] DB-Verbindung fehlgeschlagen: {host}:{port}";
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async void StartInstallClicked(object sender, RoutedEventArgs e)
    {
        if (_isBusy)
        {
            return;
        }

        var state = BuildState();
        var errors = state.Validate();

        if (errors.Length > 0)
        {
            MessageBox.Show(string.Join(Environment.NewLine, errors), "Validierung", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var installScript = FindScriptInWorkspace("install.ps1");

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

        if (SkipPreflightCheckBox.IsChecked == true)
        {
            arguments.Append(" -SkipPreflight");
        }

        if (IncludePrereleaseCheckBox.IsChecked == true)
        {
            arguments.Append(" -IncludePrerelease");
        }

        var gitHubToken = GitHubTokenBox.Password.Trim();

        StatusTextBlock.Text = "Installationsskript laeuft...";
        LogTextBox.Clear();
        SetBusy(true);

        try
        {
            await RunProcessAsync("powershell.exe", arguments.ToString(), gitHubToken);
            StatusTextBlock.Text = DryRunCheckBox.IsChecked == true
                ? "Dry-run abgeschlossen. Es wurden keine Aenderungen geschrieben."
                : "Installationsskript abgeschlossen. Runtime, Datenbank und Nginx wurden eingerichtet. Details stehen im Log.";
        }
        catch (Exception ex)
        {
            StatusTextBlock.Text = "Installationsskript fehlgeschlagen.";
            MessageBox.Show(ex.Message, "Installationsfehler", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            TryDeleteTempFile(configPath);
            SetBusy(false);
        }
    }

    private async void RunPreflightClicked(object sender, RoutedEventArgs e)
    {
        if (_isBusy)
        {
            return;
        }

        var preflightScript = FindScriptInWorkspace("preflight.ps1");

        if (preflightScript is null)
        {
            MessageBox.Show("windows\\scripts\\preflight.ps1 wurde relativ zur Anwendung nicht gefunden.", "Fehlendes Skript", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }

        StatusTextBlock.Text = "Preflight laeuft...";
        LogTextBox.Clear();
        SetBusy(true);

        try
        {
            var arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{preflightScript}\"";
            await RunProcessAsync("powershell.exe", arguments, string.Empty);
            StatusTextBlock.Text = "Preflight erfolgreich abgeschlossen.";
        }
        catch (Exception ex)
        {
            StatusTextBlock.Text = "Preflight fehlgeschlagen.";
            MessageBox.Show(ex.Message, "Preflight-Fehler", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            SetBusy(false);
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
            SslCertificatePath = SslCertificatePathTextBox.Text.Trim(),
            SslCertificateKeyPath = SslCertificateKeyPathTextBox.Text.Trim(),
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

    private string? FindScriptInWorkspace(string scriptName)
    {
        var current = new DirectoryInfo(AppContext.BaseDirectory);

        while (current is not null)
        {
            var candidate = Path.Combine(current.FullName, "windows", "scripts", scriptName);

            if (File.Exists(candidate))
            {
                return candidate;
            }

            current = current.Parent;
        }

        return null;
    }

    private async Task RunProcessAsync(string fileName, string arguments, string gitHubToken)
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

        if (!string.IsNullOrWhiteSpace(gitHubToken))
        {
            startInfo.Environment["GITHUB_TOKEN"] = gitHubToken;
        }

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

    private static async Task<bool> TestTcpConnectivityAsync(string host, int port, int timeoutMs)
    {
        using var client = new TcpClient();
        using var cts = new CancellationTokenSource(timeoutMs);

        try
        {
            await client.ConnectAsync(host, port, cts.Token);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private void SetBusy(bool busy)
    {
        _isBusy = busy;

        RunPreflightButton.IsEnabled = !busy;
        TestDatabaseButton.IsEnabled = !busy;
        PreviewConfigButton.IsEnabled = !busy;
        StartInstallButton.IsEnabled = !busy;
    }
}
