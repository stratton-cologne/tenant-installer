# Beispiel fuer lokale Release-Assets

Fuer lokale Tests kann der Installer auf vorab bereitgestellte ZIP-Dateien in [`tenant-installer/artifacts`](/Users/simon/Development/stratton.cologne/enterprise-platform/tenant-installer/artifacts) zugreifen.

Der aktuelle `v1`-Stand erwartet:

- Dateiname passend zu `artifact.file_name` im Manifest
- `sha256` passend zu `artifact.sha256` im Manifest

Spaeter kann dieselbe Staging-Schnittstelle von echten Git-Releases oder anderen Asset-Quellen gespeist werden.
