namespace TenantInstaller.Ui;

public sealed class WizardState
{
    public string InstallRoot { get; set; } = @"C:\TenantPlatform";
    public string PrimaryDomain { get; set; } = string.Empty;
    public bool UseSsl { get; set; } = true;
    public string SslCertificatePath { get; set; } = string.Empty;
    public string SslCertificateKeyPath { get; set; } = string.Empty;
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
    public string PhpRuntimeMode { get; set; } = "ScheduledTask";

    public string[] Validate()
    {
        var errors = new List<string>();

        static bool IsValidPort(string value, out int port)
        {
            if (!int.TryParse(value, out port))
            {
                return false;
            }

            return port is >= 1 and <= 65535;
        }

        if (string.IsNullOrWhiteSpace(InstallRoot))
        {
            errors.Add("InstallRoot ist erforderlich.");
        }

        if (string.IsNullOrWhiteSpace(PrimaryDomain))
        {
            errors.Add("Primary Domain ist erforderlich.");
        }

        if (string.IsNullOrWhiteSpace(AdminEmail))
        {
            errors.Add("Admin Email ist erforderlich.");
        }
        else if (!System.Net.Mail.MailAddress.TryCreate(AdminEmail, out _))
        {
            errors.Add("Admin Email ist nicht gueltig.");
        }

        if (string.IsNullOrWhiteSpace(AdminPassword))
        {
            errors.Add("Admin Passwort ist erforderlich.");
        }

        if (UseSsl)
        {
            if (string.IsNullOrWhiteSpace(SslCertificatePath))
            {
                errors.Add("Bei aktivem SSL ist ein Zertifikatspfad erforderlich.");
            }

            if (string.IsNullOrWhiteSpace(SslCertificateKeyPath))
            {
                errors.Add("Bei aktivem SSL ist ein Zertifikat-Key-Pfad erforderlich.");
            }
        }

        if (string.IsNullOrWhiteSpace(DatabasePassword))
        {
            errors.Add("Datenbank-Passwort ist erforderlich.");
        }

        if (string.IsNullOrWhiteSpace(DatabaseName))
        {
            errors.Add("DB Name ist erforderlich.");
        }

        if (string.IsNullOrWhiteSpace(DatabaseUser))
        {
            errors.Add("DB User ist erforderlich.");
        }

        if (!IsValidPort(DatabasePort, out _))
        {
            errors.Add("DB Port muss zwischen 1 und 65535 liegen.");
        }

        if (!UseLocalDatabase)
        {
            if (string.IsNullOrWhiteSpace(DatabaseHost))
            {
                errors.Add("Bei externer Datenbank ist ein DB-Host erforderlich.");
            }
        }

        if (EnableSmtp)
        {
            if (string.IsNullOrWhiteSpace(SmtpHost))
            {
                errors.Add("Bei aktivem SMTP ist ein SMTP-Host erforderlich.");
            }

            if (string.IsNullOrWhiteSpace(MailFromAddress))
            {
                errors.Add("Bei aktivem SMTP ist eine Mail-From-Adresse erforderlich.");
            }
            else if (!System.Net.Mail.MailAddress.TryCreate(MailFromAddress, out _))
            {
                errors.Add("Mail-From-Adresse ist nicht gueltig.");
            }

            if (!IsValidPort(SmtpPort, out _))
            {
                errors.Add("SMTP Port muss zwischen 1 und 65535 liegen.");
            }

            if (SmtpEncryption is not ("tls" or "ssl" or "none"))
            {
                errors.Add("SMTP Encryption muss tls, ssl oder none sein.");
            }
        }

        if (PhpRuntimeMode is not ("ScheduledTask" or "Nssm"))
        {
            errors.Add("PHP Runtime Mode muss ScheduledTask oder Nssm sein.");
        }

        return errors.ToArray();
    }
}
