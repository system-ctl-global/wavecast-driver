# WaveCast 2ch driver — corresponding source (GPL-3.0)

This repository is the complete **corresponding source** for the "WaveCast 2ch"
virtual audio driver shipped with the WaveCast application, published to satisfy
the GNU GPL, version 3, §6.

The driver is a **modified version of BlackHole** by Existential Audio
(<https://github.com/ExistentialAudio/BlackHole>), licensed under GPL-3.0.

- `Vendor/BlackHole/` — BlackHole source, exactly as shipped
  (BlackHole 0.6.1, commit `11efc147fef0ac537be1c24ea7e29e4b2a2d63c7`).
- `Packaging/build_driver.sh` — the script that rebrands and builds BlackHole
  into the WaveCast 2ch driver. It applies all modifications (name, bundle id,
  channel count, 48 kHz sample-rate lock, icon, factory UUID) at build time.

## Rebuild

```bash
xcode-select --install        # if needed
./Packaging/build_driver.sh   # produces Packaging/WaveCast2Ch.driver
```

## License

GPL-3.0 — see `LICENSE`.
