# Anforderungen Windows Tenant Installer

## Ziel

Es soll ein neuer Windows-Installer fuer das Tenant-System erstellt werden. Der Installer soll die benoetigten Releases automatisch beziehen, die Zielumgebung vorbereiten und die Anwendung ueber einen gefuehrten Wizard installieren.

## Release-Bezug

1. Der Installer soll automatisch die neuesten Releases aus folgenden Repositories beziehen:
   - `git@github.com:stratton-cologne/tenant-backend.git`
   - `git@github.com:stratton-cologne/tenant-frontend.git`
2. Es sollen jeweils die aktuellsten Release-Staende verwendet werden.
3. Das Backend-Release und das Frontend-Release sollen automatisiert heruntergeladen und fuer die Installation bereitgestellt werden.

## Wizard-Eingaben

Der Installer soll die folgenden Daten ueber einen Wizard abfragen.

### 1. Basisdaten

- Primary Domain
- SSL aktivieren oder deaktivieren
- Admin E-Mail
- Admin-Passwort

### 2. Datenbank

- Datenbank-Host
- Datenbank-Port
- Datenbank-Benutzer
- Datenbank-Passwort
- Auswahl, ob die Datenbank lokal installiert oder remote verwendet werden soll

Zusatzregel:

- Wenn die Datenbank lokal installiert werden soll, muss MariaDB durch den Installer installiert werden.

### 3. SMTP

- Auswahl, ob SMTP aktiviert werden soll
- SMTP-Host
- SMTP-Port
- SMTP-User
- SMTP-Passwort
- SMTP-Encryption
- Mail-From-Adresse

### 4. Optionale Angaben

- Optionale Tenant-ID
- Optionale Lizenzkeys

## Laufzeit- und Systemvoraussetzungen

1. Die Releases sollen mit PHP 8.2 betrieben werden.
2. Der Installer soll pruefen, ob PHP 8.2 vorhanden ist.
3. Wenn PHP 8.2 nicht vorhanden ist, soll PHP 8.2 durch den Installer installiert werden.
4. Die Anwendung soll mit Nginx betrieben werden.
5. Nginx soll als Webserver direkt durch den Installer eingerichtet werden.

## Deployment-Logik

1. Das Release aus `tenant-backend` bildet die Basis der Anwendung.
2. Das Release aus `tenant-frontend` wird in den `public`-Ordner des Backend-Releases kopiert.
3. Der Installer muss sicherstellen, dass das Frontend-Release an der korrekten Stelle innerhalb des Backend-Releases bereitgestellt wird.

## Ergebnis der Installation

Nach Abschluss der Installation soll:

1. Das neueste Backend-Release installiert sein.
2. Das neueste Frontend-Release im `public`-Ordner des Backends liegen.
3. PHP 8.2 vorhanden und einsatzbereit sein.
4. Nginx eingerichtet sein.
5. Bei lokaler Datenbankwahl MariaDB installiert und nutzbar sein.
6. Die Anwendung mit den im Wizard erfassten Konfigurationsdaten betriebsbereit vorbereitet sein.
