using System.Collections.Generic;
using System.Text;

namespace TenantInstaller.Ui;

internal static class InstallerCommandBuilder
{
    public static string BuildPreflightCommand(string scriptPath)
    {
        return $"powershell -NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"";
    }

    public static string BuildInstallCommand(string scriptPath, WizardState state, bool dryRun)
    {
        var command = new StringBuilder();
        command.Append($"powershell -NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"");
        command.Append(" -ConfigPath \"<temp-config.json>\"");

        if (dryRun)
        {
            command.Append(" -DryRun");
        }

        if (!string.IsNullOrWhiteSpace(state.AssetBaseUrl))
        {
            command.Append($" -AssetBaseUrl \"{state.AssetBaseUrl}\"");
        }

        return command.ToString();
    }

    public static string BuildPreflightArguments(string scriptPath)
    {
        return $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"";
    }

    public static string BuildInstallArguments(string scriptPath, string configPath, string assetBaseUrl, bool dryRun)
    {
        var segments = new List<string>
        {
            $"-NoProfile -ExecutionPolicy Bypass -File \"{scriptPath}\"",
            $"-ConfigPath \"{configPath}\""
        };

        if (dryRun)
        {
            segments.Add("-DryRun");
        }

        if (!string.IsNullOrWhiteSpace(assetBaseUrl))
        {
            segments.Add($"-AssetBaseUrl \"{assetBaseUrl}\"");
        }

        return string.Join(" ", segments);
    }
}
