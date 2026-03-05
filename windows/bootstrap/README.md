# Windows Bootstrap

Dieser Bereich ist optional und nur fuer Packaging/Distribution noetig.

## Wann dieser Bereich benoetigt wird

- klassische Setup-EXE fuer Verteilung
- Startmenue-/Desktop-Verknuepfungen durch Installer
- Signierung im Release-Prozess

## Standardbetrieb ohne Wrapper

Der aktuelle empfohlene Weg ist direkt:

1. WPF-UI bauen/starten
2. `windows/scripts/install.ps1` ueber die UI ausfuehren

Damit vermeiden wir einen zusaetzlichen "Installer fuer den Installer".
