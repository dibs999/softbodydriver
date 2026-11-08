# Rebuilding engine loops

Run `node tools/audio/prepare.cjs` from the repository root. It reads 24 kHz mono,
signed 16-bit little-endian PCM sources from `build-wheels/asset-sources`, or the
directory named by `ENGINE_PCM_DIR`. Decode the credited HQ recordings, for example:

```text
ffmpeg -i renault.mp3 -ac 1 -ar 24000 -f s16le renault.pcm
```

Use names `renault.pcm`, `rover.pcm` and `maserati.pcm`. Source links, authors and
licenses are in `game/ASSET_CREDITS.md`; source recordings are not included.
`clips.json` specifies each output's source name, start/end seconds and tracked
harmonic frequency in Hz. The filename's RPM is a playback reference, estimated
from the harmonics, not calibrated vehicle telemetry. The tracked harmonic need
not be the firing fundamental (the V6 2000 RPM loop tracks its stronger fifth order).

The dependency-free processor removes DC / recording tones, follows local pitch,
cross-correlates a loop seam, crossfades it and matches RMS with peak headroom.
Godot crossfades both RPM and load/release layers and follows physical clutch / shift
telemetry. High V6 RPM remains transposed from the limited sustained source range;
the V8 quiet layer is a lower-load excerpt, not a separately recorded coast-down.
