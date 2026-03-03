namespace TenantInstaller.Ui;

public sealed class WizardState
{
    public string PrimaryDomain { get; set; } = string.Empty;
    public bool UseSsl { get; set; } = true;
    public string AdminEmail { get; set; } = string.Empty;
    public string AdminPassword { get; set; } = string.Empty;

    public bool UseLocalDatabase { get; set; }
    public string DatabaseHost { get; set; } = "127.0.0.1";
    public string DatabasePort { get; set; } = "3306";
    public string DatabaseName { get; set; } = "tenant_platform";
    public string DatabaseUser { get; set; } = "tenant_user";
    public string DatabasePassword { get; set; } = string.Empty;

    public bool EnableSmtp { get; set; }
    public string SmtpHost { get; set; } = string.Empty;
    public string SmtpPort { get; set; } = "587";
    public string SmtpUser { get; set; } = string.Empty;
    public string SmtpPassword { get; set; } = string.Empty;
    public string SmtpEncryption { get; set; } = "tls";
    public string MailFromAddress { get; set; } = string.Empty;

    public string TenantId { get; set; } = string.Empty;
    public string LicenseKeys { get; set; } = string.Empty;
}
