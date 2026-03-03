# Example Module

Dies ist eine minimale Test-Fixture fuer den Modul-Manager.

## Ziel

Das Paket dient ausschliesslich dazu, den lokalen Installationsfluss des Modul-Managers zu pruefen.

## Inhalt

- `module.json`
- `backend/`
- `frontend/`

## Lokales ZIP bauen

Empfohlen ueber den Build-Helper:

```bash
./tenant-installer/tools/build/build-example-module.sh
```

Alternativ direkt aus dem Ordner `tenant-installer/module-manager/fixtures/example-module`:

```bash
zip -r example-module-1.0.0.zip module.json backend frontend
```

Das erzeugte ZIP kann anschliessend mit den Modul-Manager-Skripten getestet werden.
