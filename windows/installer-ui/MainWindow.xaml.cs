using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace TenantInstaller.Ui;

public partial class MainWindow : Window
{
    private readonly WizardState _state = new();
    private bool _isRunning;
    private string _lastOperationName = "Noch kein Lauf";
    private string _lastPhaseName = "Noch keine Phase";

    public MainWindow()
    {
        InitializeComponent();
        StepList.SelectedIndex = 0;
        WizardTabs.SelectedIndex = 0;
        SyncStateToUi();
        RefreshCommandPreview();
        RefreshSummary();
        UpdateResultScreen(
            "Noch kein Installationslauf ausgefuehrt",
            "Fuehre Preflight oder Install im Schritt 'Quelle & Pruefung' aus. Das Ergebnis erscheint anschliessend hier.",
            "#F8FAFD",
            "#D2D9E3",
            "#19324D");
        ExecutionPhaseTextBlock.Text = "Noch keine Phase aktiv.";
        UpdateButtons();
    }

    private void StepList_OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (StepList.SelectedIndex < 0)
        {
            return;
        }

        WizardTabs.SelectedIndex = StepList.SelectedIndex;
        UpdateButtons();
    }

    private void BackButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_isRunning || StepList.SelectedIndex <= 0)
        {
            return;
        }

        CaptureUiIntoState();
        StepList.SelectedIndex -= 1;
    }

    private void NextButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_isRunning)
        {
            return;
        }

        CaptureUiIntoState();

        if (StepList.SelectedIndex < WizardTabs.Items.Count - 1)
        {
            StepList.SelectedIndex += 1;
            if (StepList.SelectedIndex == WizardTabs.Items.Count - 1)
            {
                RefreshSummary();
            }
            return;
        }

        RefreshSummary();
        MessageBox.Show(
            "Die Windows-GUI kann jetzt Preflight und Install ueber die vorhandenen PowerShell-Skripte starten. Fuer den Produktivstand fehlen vor allem Signierung, EXE-Packaging und feinere Fehlerdialoge.",
            "Windows Installer",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void RefreshButton_OnClick(object sender, RoutedEventArgs e)
    {
        if (_isRunning)
        {
            return;
        }

        CaptureUiIntoState();
        RefreshCommandPreview();
        RefreshSummary();
    }

    private void EnableSmtpCheckBox_OnChanged(object sender, RoutedEventArgs e)
    {
        var enabled = EnableSmtpCheckBox.IsChecked == true;
        MailHostTextBox.IsEnabled = enabled;
        MailPortTextBox.IsEnabled = enabled;
        MailUsernameTextBox.IsEnabled = enabled;
        MailPasswordBox.IsEnabled = enabled;
        MailEncryptionTextBox.IsEnabled = enabled;
        MailFromAddressTextBox.IsEnabled = enabled;
    }

    private async void RunPreflightButton_OnClick(object sender, RoutedEventArgs e)
    {
        CaptureUiIntoState();
        RefreshCommandPreview();
        RefreshSummary();

        var (_, preflightPath) = GetScriptPaths();
        await RunPowerShellAsync(
            InstallerCommandBuilder.BuildPreflightArguments(preflightPath),
            "Preflight",
            isInstallRun: false);
    }

    private async void RunInstallButton_OnClick(object sender, RoutedEventArgs e)
    {
        CaptureUiIntoState();

        if (!ValidateRequiredInputs())
        {
            return;
        }

        RefreshCommandPreview();
        RefreshSummary();

        var (installPath, _) = GetScriptPaths();
        var tempConfigPath = string.Empty;

        try
        {
            tempConfigPath = await WriteTempConfigAsync();
            var arguments = InstallerCommandBuilder.BuildInstallArguments(
                installPath,
                tempConfigPath,
                _state.AssetBaseUrl,
                DryRunCheckBox.IsChecked == true);

            var success = await RunPowerShellAsync(arguments, "Install");
            if (success)
            {
                StepList.SelectedIndex = WizardTabs.Items.Count - 1;
            }
        }
        finally
        {
            if (!string.IsNullOrWhiteSpace(tempConfigPath) && File.Exists(tempConfigPath))
            {
                File.Delete(tempConfigPath);
            }
        }
    }

    private void CaptureUiIntoState()
    {
        _state.AppRoot = AppRootTextBox.Text.Trim();
        _state.Domain = DomainTextBox.Text.Trim();
        _state.UseSsl = UseSslCheckBox.IsChecked == true;
        _state.AdminEmail = AdminEmailTextBox.Text.Trim();
        _state.AdminPassword = AdminPasswordBox.Password;
        _state.DbHost = DbHostTextBox.Text.Trim();
        _state.DbPort = DbPortTextBox.Text.Trim();
        _state.DbName = DbNameTextBox.Text.Trim();
        _state.DbUser = DbUserTextBox.Text.Trim();
        _state.DbPassword = DbPasswordBox.Password;
        _state.EnableSmtp = EnableSmtpCheckBox.IsChecked == true;
        _state.MailHost = MailHostTextBox.Text.Trim();
        _state.MailPort = MailPortTextBox.Text.Trim();
        _state.MailUsername = MailUsernameTextBox.Text.Trim();
        _state.MailPassword = MailPasswordBox.Password;
        _state.MailEncryption = MailEncryptionTextBox.Text.Trim();
        _state.MailFromAddress = MailFromAddressTextBox.Text.Trim();
        _state.TenantId = TenantIdTextBox.Text.Trim();
        _state.LicenseKey = LicenseKeyTextBox.Text.Trim();
        _state.RunSeeders = RunSeedersCheckBox.IsChecked == true;
        _state.AssetBaseUrl = AssetBaseUrlTextBox.Text.Trim();
    }

    private void SyncStateToUi()
    {
        AppRootTextBox.Text = _state.AppRoot;
        DomainTextBox.Text = _state.Domain;
        UseSslCheckBox.IsChecked = _state.UseSsl;
        AdminEmailTextBox.Text = _state.AdminEmail;
        DbHostTextBox.Text = _state.DbHost;
        DbPortTextBox.Text = _state.DbPort;
        DbNameTextBox.Text = _state.DbName;
        DbUserTextBox.Text = _state.DbUser;
        EnableSmtpCheckBox.IsChecked = _state.EnableSmtp;
        MailHostTextBox.Text = _state.MailHost;
        MailPortTextBox.Text = _state.MailPort;
        MailUsernameTextBox.Text = _state.MailUsername;
        MailEncryptionTextBox.Text = _state.MailEncryption;
        MailFromAddressTextBox.Text = _state.MailFromAddress;
        TenantIdTextBox.Text = _state.TenantId;
        LicenseKeyTextBox.Text = _state.LicenseKey;
        RunSeedersCheckBox.IsChecked = _state.RunSeeders;
        AssetBaseUrlTextBox.Text = _state.AssetBaseUrl;
        EnableSmtpCheckBox_OnChanged(this, new RoutedEventArgs());
    }

    private void RefreshCommandPreview()
    {
        var (installPath, preflightPath) = GetScriptPaths();

        PreflightCommandTextBox.Text = InstallerCommandBuilder.BuildPreflightCommand(preflightPath);
        InstallCommandTextBox.Text = InstallerCommandBuilder.BuildInstallCommand(
            installPath,
            _state,
            DryRunCheckBox.IsChecked == true);
    }

    private void RefreshSummary()
    {
        var summary = new StringBuilder();
        summary.AppendLine("Windows Installer Wizard Summary");
        summary.AppendLine();
        summary.AppendLine($"Application Root: {_state.AppRoot}");
        summary.AppendLine($"Domain: {_state.Domain}");
        summary.AppendLine($"SSL: {(_state.UseSsl ? "yes" : "no")}");
        summary.AppendLine($"Admin Email: {_state.AdminEmail}");
        summary.AppendLine($"DB Host: {_state.DbHost}");
        summary.AppendLine($"DB Port: {_state.DbPort}");
        summary.AppendLine($"DB Name: {_state.DbName}");
        summary.AppendLine($"DB User: {_state.DbUser}");
        summary.AppendLine($"SMTP Enabled: {(_state.EnableSmtp ? "yes" : "no")}");
        summary.AppendLine($"Tenant ID: {(string.IsNullOrWhiteSpace(_state.TenantId) ? "(none)" : _state.TenantId)}");
        summary.AppendLine($"License Key: {(string.IsNullOrWhiteSpace(_state.LicenseKey) ? "(none)" : "[provided]")}");
        summary.AppendLine($"Run Seeders: {(_state.RunSeeders ? "yes" : "no")}");
        summary.AppendLine($"Asset Base URL: {(string.IsNullOrWhiteSpace(_state.AssetBaseUrl) ? "(local artifacts)" : _state.AssetBaseUrl)}");
        summary.AppendLine($"Dry Run: {(DryRunCheckBox.IsChecked == true ? "yes" : "no")}");
        summary.AppendLine($"Last Operation: {_lastOperationName}");
        summary.AppendLine($"Last Phase: {_lastPhaseName}");
        summary.AppendLine($"Current Status: {ExecutionStatusTextBlock.Text}");
        summary.AppendLine();
        summary.AppendLine("Prepared Commands");
        summary.AppendLine("-----------------");
        summary.AppendLine(PreflightCommandTextBox.Text);
        summary.AppendLine();
        summary.AppendLine(InstallCommandTextBox.Text);
        summary.AppendLine();
        summary.AppendLine("Execution Model");
        summary.AppendLine("---------------");
        summary.AppendLine("1. GUI schreibt eine temporaere JSON-Konfiguration");
        summary.AppendLine("2. install.ps1 laedt diese ueber -ConfigPath");
        summary.AppendLine("3. Live-Ausgabe erscheint direkt im Wizard");

        SummaryTextBox.Text = summary.ToString();
    }

    private (string InstallPath, string PreflightPath) GetScriptPaths()
    {
        var baseDir = AppDomain.CurrentDomain.BaseDirectory;
        var scriptsDir = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "scripts"));
        var installPath = Path.Combine(scriptsDir, "install.ps1");
        var preflightPath = Path.Combine(scriptsDir, "preflight.ps1");
        return (installPath, preflightPath);
    }

    private bool ValidateRequiredInputs()
    {
        if (string.IsNullOrWhiteSpace(_state.Domain))
        {
            MessageBox.Show("Domain ist erforderlich.", "Validierung", MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }

        if (string.IsNullOrWhiteSpace(_state.AdminEmail))
        {
            MessageBox.Show("Admin E-Mail ist erforderlich.", "Validierung", MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }

        if (string.IsNullOrWhiteSpace(_state.AdminPassword))
        {
            MessageBox.Show("Admin Passwort ist erforderlich.", "Validierung", MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }

        if (string.IsNullOrWhiteSpace(_state.DbPassword))
        {
            MessageBox.Show("Datenbank-Passwort ist erforderlich.", "Validierung", MessageBoxButton.OK, MessageBoxImage.Warning);
            return false;
        }

        if (_state.EnableSmtp && string.IsNullOrWhiteSpace(_state.MailFromAddress))
        {
            _state.MailFromAddress = _state.AdminEmail;
            MailFromAddressTextBox.Text = _state.MailFromAddress;
        }

        return true;
    }

    private async Task<string> WriteTempConfigAsync()
    {
        var directory = Path.Combine(Path.GetTempPath(), "tenant-installer-ui");
        Directory.CreateDirectory(directory);

        var filePath = Path.Combine(directory, $"install-input-{Guid.NewGuid():N}.json");
        var payload = new
        {
            _state.AppRoot,
            _state.Domain,
            _state.UseSsl,
            _state.AdminEmail,
            _state.AdminPassword,
            _state.DbHost,
            _state.DbPort,
            _state.DbName,
            _state.DbUser,
            _state.DbPassword,
            _state.EnableSmtp,
            _state.MailHost,
            _state.MailPort,
            MailUsername = _state.MailUsername,
            _state.MailPassword,
            _state.MailEncryption,
            MailFromAddress = string.IsNullOrWhiteSpace(_state.MailFromAddress) ? _state.AdminEmail : _state.MailFromAddress,
            _state.TenantId,
            _state.LicenseKey,
            _state.RunSeeders
        };

        var json = JsonSerializer.Serialize(payload, new JsonSerializerOptions
        {
            WriteIndented = true
        });

        await File.WriteAllTextAsync(filePath, json);
        return filePath;
    }

    private async Task<bool> RunPowerShellAsync(string arguments, string operationName, bool isInstallRun = true)
    {
        if (_isRunning)
        {
            return false;
        }

        _lastOperationName = operationName;
        SetRunningState(true, $"{operationName} laeuft...");
        SetProgressState(isRunning: true, completed: false, success: false);
        SetPhase("Starte Prozessinitialisierung", 10);
        UpdateResultScreen(
            $"{operationName} wird ausgefuehrt",
            "Die Windows-Engine laeuft aktuell. Die Live-Ausgabe wird unten mitgeschrieben.",
            "#FFF7E8",
            "#E5C77A",
            "#7A5600");
        ExecutionLogTextBox.Clear();
        AppendLogLine($"[INFO] Starte {operationName}");
        AppendLogLine($"[INFO] powershell {arguments}");

        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = arguments,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            using var process = new Process
            {
                StartInfo = startInfo,
                EnableRaisingEvents = true
            };

            process.OutputDataReceived += (_, args) =>
            {
                if (args.Data is not null)
                {
                    TrackExecutionPhase(args.Data, operationName, isInstallRun);
                    AppendLogLine(args.Data);
                }
            };

            process.ErrorDataReceived += (_, args) =>
            {
                if (args.Data is not null)
                {
                    TrackExecutionPhase(args.Data, operationName, isInstallRun);
                    AppendLogLine($"[ERR] {args.Data}");
                }
            };

            if (!process.Start())
            {
                throw new InvalidOperationException("PowerShell-Prozess konnte nicht gestartet werden.");
            }

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            await process.WaitForExitAsync();

            var success = process.ExitCode == 0;
            var statusText = success
                ? $"{operationName} erfolgreich abgeschlossen."
                : $"{operationName} mit Exit-Code {process.ExitCode} beendet.";

            ExecutionStatusTextBlock.Text = statusText;
            AppendLogLine(success ? "[INFO] Lauf erfolgreich beendet." : $"[FAIL] Lauf beendet mit Exit-Code {process.ExitCode}.");
            SetProgressState(isRunning: false, completed: true, success: success);
            SetPhase(success ? $"{operationName} abgeschlossen" : $"{operationName} beendet", 100);
            UpdateResultScreen(
                success ? $"{operationName} erfolgreich" : $"{operationName} fehlgeschlagen",
                success
                    ? (isInstallRun
                        ? "Der Installationslauf wurde erfolgreich beendet. Der naechste Schritt ist bei Bedarf die Runtime-Aktivierung ueber activate-runtime.ps1."
                        : "Der Preflight wurde erfolgreich beendet. Die Voraussetzungen sind aus Sicht des Scripts erfuellt.")
                    : $"Der Lauf endete mit Exit-Code {process.ExitCode}. Pruefe die Live-Ausgabe und behebe den ersten Fehler vor einem erneuten Start.",
                success ? "#EDF8F0" : "#FDEEEE",
                success ? "#7AB68B" : "#D67D7D",
                success ? "#1C5F33" : "#8A2525");
            return success;
        }
        catch (Exception ex)
        {
            ExecutionStatusTextBlock.Text = $"{operationName} fehlgeschlagen.";
            AppendLogLine($"[FAIL] {ex.Message}");
            SetProgressState(isRunning: false, completed: true, success: false);
            SetPhase($"{operationName} fehlgeschlagen", 100);
            UpdateResultScreen(
                $"{operationName} fehlgeschlagen",
                ex.Message,
                "#FDEEEE",
                "#D67D7D",
                "#8A2525");
            MessageBox.Show(ex.Message, $"{operationName} fehlgeschlagen", MessageBoxButton.OK, MessageBoxImage.Error);
            return false;
        }
        finally
        {
            SetRunningState(false, ExecutionStatusTextBlock.Text);
            RefreshSummary();
        }
    }

    private void AppendLogLine(string line)
    {
        Dispatcher.Invoke(() =>
        {
            ExecutionLogTextBox.AppendText(line + Environment.NewLine);
            ExecutionLogTextBox.ScrollToEnd();
        });
    }

    private void SetRunningState(bool isRunning, string statusText)
    {
        _isRunning = isRunning;
        ExecutionStatusTextBlock.Text = statusText;
        BackButton.IsEnabled = !_isRunning && StepList.SelectedIndex > 0;
        RefreshButton.IsEnabled = !_isRunning;
        NextButton.IsEnabled = !_isRunning;
        RunPreflightButton.IsEnabled = !_isRunning;
        RunInstallButton.IsEnabled = !_isRunning;
    }

    private void SetProgressState(bool isRunning, bool completed, bool success)
    {
        ExecutionProgressBar.IsIndeterminate = false;

        if (isRunning)
        {
            ExecutionProgressBar.Value = 10;
            return;
        }

        if (!completed)
        {
            ExecutionProgressBar.Value = 0;
            return;
        }

        ExecutionProgressBar.Value = success ? 100 : 100;
    }

    private void SetPhase(string phaseName, double progressValue)
    {
        _lastPhaseName = phaseName;
        Dispatcher.Invoke(() =>
        {
            ExecutionPhaseTextBlock.Text = $"Aktuelle Phase: {phaseName}";
            if (!ExecutionProgressBar.IsIndeterminate)
            {
                ExecutionProgressBar.Value = progressValue;
            }
        });
    }

    private void TrackExecutionPhase(string line, string operationName, bool isInstallRun)
    {
        if (!isInstallRun)
        {
            if (line.Contains("Starte Windows-Preflight", StringComparison.OrdinalIgnoreCase))
            {
                SetPhase("Preflight gestartet", 25);
            }
            else if (line.Contains("Preflight erfolgreich abgeschlossen", StringComparison.OrdinalIgnoreCase))
            {
                SetPhase("Preflight erfolgreich", 100);
            }
            else if (line.Contains("Preflight mit Fehlern abgeschlossen", StringComparison.OrdinalIgnoreCase))
            {
                SetPhase("Preflight mit Fehlern", 100);
            }

            return;
        }

        if (line.Contains("Starte Windows-Installationsfluss", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Initialisierung", 10);
            return;
        }

        if (line.Contains("Backend-Manifest:", StringComparison.OrdinalIgnoreCase) || line.Contains("Frontend-Manifest:", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Release-Auswahl", 20);
            return;
        }

        if (line.Contains("Artefakt gestaged:", StringComparison.OrdinalIgnoreCase) || line.Contains("Artefakt geladen:", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Artefakte bereitgestellt", 35);
            return;
        }

        if (line.Contains("Entpackt:", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Artefakte entpackt", 45);
            return;
        }

        if (line.Contains("Generierte Dateien erstellt", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Konfiguration gerendert", 55);
            return;
        }

        if (line.Contains("Basis-Deploy abgeschlossen", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Basis-Deploy abgeschlossen", 70);
            return;
        }

        if (line.Contains("Starte composer install", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Composer-Install", 78);
            return;
        }

        if (line.Contains("Generiere Application Key", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Application Key", 84);
            return;
        }

        if (line.Contains("Fuehre Migrationen aus", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Migrationen", 90);
            return;
        }

        if (line.Contains("Fuehre Seeder aus", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Seeder", 94);
            return;
        }

        if (line.Contains("Installer-State gespeichert", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Installer-State gespeichert", 97);
            return;
        }

        if (line.Contains("Success-Marker geschrieben", StringComparison.OrdinalIgnoreCase))
        {
            SetPhase($"{operationName}: Abschlussmarkierung", 99);
        }
    }

    private void UpdateResultScreen(string title, string message, string backgroundColor, string borderColor, string foregroundColor)
    {
        ExecutionResultTitleTextBlock.Text = title;
        ExecutionResultMessageTextBlock.Text = message;
        ExecutionResultBorder.Background = (Brush)new BrushConverter().ConvertFromString(backgroundColor)!;
        ExecutionResultBorder.BorderBrush = (Brush)new BrushConverter().ConvertFromString(borderColor)!;
        ExecutionResultTitleTextBlock.Foreground = (Brush)new BrushConverter().ConvertFromString(foregroundColor)!;
    }

    private void UpdateButtons()
    {
        BackButton.IsEnabled = !_isRunning && StepList.SelectedIndex > 0;
        NextButton.IsEnabled = !_isRunning;
        NextButton.Content = StepList.SelectedIndex == WizardTabs.Items.Count - 1 ? "Fertig" : "Weiter";
    }
}
