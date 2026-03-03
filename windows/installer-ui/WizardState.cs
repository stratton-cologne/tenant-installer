namespace TenantInstaller.Ui;

public sealed class WizardState
{
    public string AppRoot { get; set; } = @"C:\TenantPlatform";
    public string Domain { get; set; } = string.Empty;
    public bool UseSsl { get; set; } = true;
    public string AdminEmail { get; set; } = string.Empty;
    public string AdminPassword { get; set; } = string.Empty;
    public string DbHost { get; set; } = "127.0.0.1";
    public string DbPort { get; set; } = "3306";
    public string DbName { get; set; } = "tenant_platform";
    public string DbUser { get; set; } = "tenant_user";
    public string DbPassword { get; set; } = string.Empty;
    public bool EnableSmtp { get; set; }
    public string MailHost { get; set; } = string.Empty;
    public string MailPort { get; set; } = "587";
    public string MailUsername { get; set; } = string.Empty;
    public string MailPassword { get; set; } = string.Empty;
    public string MailEncryption { get; set; } = "tls";
    public string MailFromAddress { get; set; } = string.Empty;
    public string TenantId { get; set; } = string.Empty;
    public string LicenseKey { get; set; } = string.Empty;
    public bool RunSeeders { get; set; }
    public string AssetBaseUrl { get; set; } = string.Empty;
}
