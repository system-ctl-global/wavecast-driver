# WaveCast driver — corresponding source (GPL-3.0)

This repository is the complete **corresponding source** for the "WaveCast"
virtual audio driver shipped with the WaveCast application, published to satisfy
the GNU GPL, version 3, §6.

The driver is a **modified version of BlackHole** by Existential Audio
(<https://github.com/ExistentialAudio/BlackHole>), licensed under GPL-3.0.

- `Vendor/BlackHole/` — BlackHole source, exactly as shipped.
- `Packaging/build_driver.sh` — the script that rebrands and builds BlackHole
  into the WaveCast driver. It applies all modifications (name, bundle id,
  16-channel count, 48 kHz sample-rate lock, icon, factory UUID) at build time.

## Rebuild

```bash
xcode-select --install        # if needed
./Packaging/build_driver.sh   # produces Packaging/WaveCast.driver
```

## License

GPL-3.0 — see `LICENSE`.
