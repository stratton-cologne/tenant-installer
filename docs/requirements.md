# Technisches Pflichtenheft

## Produktziel

Es wird ein neues Installer-Repository fuer die Bereitstellung eines Tenant-Systems auf Windows-Servern und Ubuntu-Servern aufgebaut. Das Repository deckt sowohl die Erstinstallation des Basissystems als auch spaetere Wartungsablaeufe ab.

## Scope

Der Installer unterstuetzt in `v1`:

- Interaktive Erstinstallation
- Reinen Pruefmodus ohne Aenderungen am Zielsystem
- Update mit Backup und Rollback-Snapshot
- Repair bestehender Installationen
- Uninstall mit Rueckfrage zum Erhalt von Datenbank und Datenbestand
- Separaten Modul-Manager fuer lokale Modulpakete

Der Installer darf Teile der Infrastruktur automatisiert nachinstallieren, sofern dies auf dem Zielsystem technisch vertretbar ist.

## Zielplattformen

### Ubuntu

- Unterstuetzte Zielversion: `22.04` aufwaerts
- Native Installation ohne Docker
- Standard-Webserver: `Nginx`
- Prozesssteuerung: `Supervisor` und `systemd`
- Laravel-Scheduler wird automatisch eingerichtet
- Optionales SSL per `Let's Encrypt`

### Windows Server

- Unterstuetzte Zielversion: `2016` aufwaerts
- Native Installation ohne Docker
- Standard-Webserver: `Nginx`
- `IIS` wird nicht verwendet
- `Nginx` wird durch den Installer selbst mit ausgeliefert und eingerichtet
- Hintergrundprozesse laufen ueber einen eigenen Service-Wrapper fuer `php artisan queue:work` und den Scheduler

## Installationsarten

### Windows

- `v1`: signiertes `EXE` mit Assistent
- Spaeter optional: `MSI`

### Ubuntu

- `v1`: interaktives Setup-Script
- Spaeter optional: Paketierung als `.deb`

## Release- und Artefaktstrategie

- Der Installer zieht immer die neueste stabile Release-Version.
- Als stabil gelten nur semantische Releases ohne `alpha`, `beta`, `rc`.
- Artefakte werden nicht aus Source auf dem Kundensystem gebaut, sondern als vorbereitete ZIP-Dateien bezogen.
- `tenant-backend` und `tenant-frontend` duerfen unterschiedliche Release-Staende haben.
- Jedes Release-Artefakt muss ein Metafile enthalten, das mindestens diese Informationen traegt:
  - Version
  - Build-Zeit
  - Release-Kanal
  - Kompatibilitaetshinweise zu Gegenkomponenten
- Bei abweichenden oder fraglichen Kompatibilitaeten warnt der Installer, blockiert aber in `v1` nicht hart.
- Vor Ausfuehrung zeigt der Installer die erkannte Zielversion an und laesst den Benutzer diese bestaetigen.

## Backend-Installation

- Quelle: vorbereitete Release-ZIP des Laravel-Backends
- Der Installer erzeugt die `.env` vollstaendig aus den erfassten Eingaben.
- Der Installer prueft auf `PHP 8.2`, benoetigte PHP-Erweiterungen, `Composer` sowie MySQL/MariaDB-Client.
- Falls Voraussetzungen fehlen, zeigt der Installer eine gefuehrte Installationsanleitung an.
- Falls vertretbar, duerfen Teilkomponenten automatisiert nachinstalliert werden.
- `Composer` wird nicht im Release vorgebuendelt vorausgesetzt.
- Nach dem Deploy fuehrt der Installer mindestens folgende Schritte aus:
  - `composer install`
  - `php artisan key:generate`
  - Datenbankmigrationen
  - optionale Seeder
  - Einrichtung von Queue-Worker und Scheduler

## Frontend-Installation

- Quelle: vorbereitete Release-ZIP mit fertigem `dist`
- Das Frontend wird als vollstaendige SPA unter `/` betrieben.
- Deployment erfolgt in den `public`-Bereich der Laravel-Anwendung.
- Die API-URL wird ueber die `.env` bereitgestellt.
- Bei Updates werden bestehende Frontend-Artefakte gesichert und ersetzt.

## Datenbank

- Unterstuetzte Datenbanken: `MySQL` und `MariaDB`
- Nutzung vorhandener Datenbank ist moeglich.
- Optional kann eine lokale Datenbankinstallation erfolgen.
- Bei lokaler Installation ist `MariaDB` die bevorzugte Standardwahl.
- Wenn administrative Zugangsdaten vorliegen, darf der Installer Datenbank und Benutzer automatisch anlegen.
- Bestehende Datenbanken muessen erkannt werden.
- Migrationen muessen sicher gegen bestehende Installationen laufen koennen.

## SSL und Domain

- Eine Domain wird waehrend der Installation abgefragt.
- SSL ist optional.
- Betrieb ohne SSL ist erlaubt, aber mit klarer Warnung.
- Unter Ubuntu soll optional `Let's Encrypt` automatisiert eingerichtet werden.
- Vor `Let's Encrypt` prueft der Installer DNS-Erreichbarkeit sowie Ports `80` und `443`.
- Proxy-Unterstuetzung fuer restriktive Netzwerke ist vorgesehen.

## Erfasste Eingaben

Mindestens folgende Eingaben werden interaktiv erfasst:

- Admin-E-Mail
- Admin-Passwort
- Datenbankzugang
- Optionale SMTP-Daten
- Optionale Tenant-ID
- Optionale Lizenzkeys
- Domain

### Validierung

- E-Mail-Format pruefen
- Datenbankverbindung pruefen
- Eingaben maskieren, wenn es sich um geheime Werte handelt
- Optionalen SMTP-Test nur auf ausdruecklichen Wunsch ausfuehren
- Lizenz- oder Tenant-Daten sind in `v1` optional

## SMTP

- Zunaechst nur generisches SMTP
- SMTP ist optional
- Zugangsdaten werden verschluesselt gespeichert
- Eine Testmail kann auf Wunsch versendet werden

## Tenant und Lizenz

- Tenant-ID und Lizenzkey sind nicht verpflichtend
- Die Installation muss auch ohne diese Daten moeglich sein
- Eine spaetere Anbindung an Core-API oder Lizenzserver ist gewuenscht, aber fuer `v1` nicht zwingend
- Bei ungueltigen Lizenzdaten wird eine Fehlermeldung ausgegeben
- Offline-Aktivierung ist nicht vorgesehen

## Sicherheit

- Installer-Zustand wird als verschluesselte Datei im Installationsverzeichnis unter `installer/state` abgelegt
- Diese Datei wird auch fuer `Uninstall` verwendet
- Die Entschluesselung uebernimmt der Installer
- Sensible Werte duerfen nicht ausserhalb des Zielsystems zwischengespeichert werden
- Passworteingabe muss maskiert sein
- Installer-Logs muessen Geheimnisse maskieren
- Das Admin-Passwort wird im Zielsystem serverseitig gehasht angelegt

## Modul-Manager

- Der Modul-Manager ist vom Basis-Installer getrennt
- Modulinstallation erfolgt per lokaler Dateiauswahl
- Paketformat eines Moduls:
  - `module.json`
  - `backend/`
  - `frontend/`
- Backend-Dateien werden nach `tenant-backend/modules/...` entpackt
- Frontend-Dateien werden nach `public/modules/...` entpackt
- Unterstuetzte Aktionen:
  - Installieren
  - Aktualisieren
  - Deinstallieren
  - Aktivieren
  - Deaktivieren
- Nach Installation oder Update werden notwendige Migrationen und technische Nacharbeiten automatisch ausgefuehrt
- Eine harte Kompatibilitaetspruefung gegen die Tenant-Version findet in `v1` nicht statt

## Logging

- Ubuntu-Logs liegen unter `/var/log/tenant-installer`
- Windows-Logs liegen im Installationsordner
- Getrennte Logs fuer:
  - Install
  - Update
  - Module
  - Repair
- Log-Rotation oder Archivierung ist vorgesehen
