# Validation

Dieser Bereich enthaelt einfache Pruefwerkzeuge fuer `v1`.

## Release-Manifest pruefen

Beispiel:

```bash
./tenant-installer/tools/validation/validate-release-manifest.sh \
  tenant-installer/shared/manifests/example.tenant-backend.release.json
```

Aktuell validiert das Skript die wichtigsten Mindestregeln:

- Pflichtfelder vorhanden
- `stable` als Release-Kanal
- stabile semantische Version ohne Pre-Release-Suffix
- gueltiger `sha256`-Hash

## Installer-State entschluesseln

Beispiel:

```bash
./tenant-installer/tools/validation/decrypt-installer-state.sh \
  /var/www/tenant-platform/installer/state/install-state.enc.json \
  'admin-password'
```

Das Skript dient als technische Pruefhilfe fuer den aktuellen `v1`-Stand des verschluesselten Installer-State.
