# Build

Hilfsskripte fuer lokale Test- und Paket-Builds.

## Beispiel-Modul bauen

```bash
./tenant-installer/tools/build/build-example-module.sh
```

Das Skript erzeugt standardmaessig:

- `tenant-installer/artifacts/modules/example-module-1.0.0.zip`

Optional kann ein anderer Zielordner angegeben werden:

```bash
./tenant-installer/tools/build/build-example-module.sh --output-dir /tmp/module-builds
```
