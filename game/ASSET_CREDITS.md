# Asset credits

Surface photographs and recordings are CC0 unless otherwise stated below.

## Engine audio

Current driving profiles use one source vehicle per engine family:

- I4: [Renault 19 underhood acceleration by lovretta](https://freesound.org/people/lovretta/sounds/141240/) — [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Idle, acceleration and coast-down excerpts.
- V6: [land rover sport v6 engine revving by jerry.berumen](https://freesound.org/people/jerry.berumen/sounds/772800/) — [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/). Used via Freesound's HQ preview; trimmed, filtered, pitch-stabilised, looped and level-matched. The recording has a limited sustained RPM range: higher playback RPM is transposed, not a separately recorded high-RPM engine.
- V8: [Maserati GranTurismo Switch to Sport Mode and Launch by myeclecticself](https://freesound.org/people/myeclecticself/sounds/585215/) — [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Idle and launch excerpts. Its quiet layer uses the later, lower-load portion of the launch; this is not a dedicated throttle-off recording.

All reference RPM values are estimates. The source intervals and processing are in
`tools/audio/clips.json` and `tools/audio/prepare.cjs`. No endorsement by the authors
or vehicle manufacturers is implied.

Legacy clips retained in the asset folder (not selected by the current profiles):

The game uses trimmed, filtered and level-matched excerpts. The loop points were crossfaded, and the reference RPMs are estimated from the recordings.

The revised loops use longer excerpts where available, remove persistent recording tones,
and stabilise the recorded firing frequency before crossfading. Playback now keeps loops
running continuously across RPM bands and follows the simulated shift torque cut.
These remain shared engine-family recordings, not recordings of the fictional individual cars.

- Inline-four idle from [Elantra Engine Idle and Rev by microman502](https://freesound.org/people/microman502/sounds/865228/).
- Inline-four under load from [Car Engine Contact Recording — Mini Cooper S 2019 by TheLittleCrow](https://freesound.org/people/TheLittleCrow/sounds/669618/).
- V6 from [Cars — truck interior while driving 2 (loud) by jodybruchon](https://freesound.org/people/jodybruchon/sounds/519577/) and [Nissan Maxima burnout by audible-edge](https://freesound.org/people/audible-edge/sounds/71740/).
- V8 from [Maserati GranTurismo Switch to Sport Mode and Launch by myeclecticself](https://freesound.org/people/myeclecticself/sounds/585215/) and [Chevrolet Caprice by romanholtwick](https://freesound.org/people/romanholtwick/sounds/391671/).
- Gear selection from [gear select.wav by greatsoundstube](https://freesound.org/people/greatsoundstube/sounds/629324/).

## Map surfaces

- [Asphalt Track by Dimitrios Savva](https://polyhaven.com/a/asphalt_track).
- [Sandy Gravel by Charlotte Baglioni](https://polyhaven.com/a/sandy_gravel).
- [Leafy Grass by Charlotte Baglioni](https://polyhaven.com/a/leafy_grass).
- [Coast Sand 05 by Rob Tuytel and Dario Barresi](https://polyhaven.com/a/coast_sand_05).
- [Concrete Pavement by Charlotte Baglioni](https://polyhaven.com/a/concrete_pavement).

## Imported vehicle model

[Car Concept](https://github.com/KhronosGroup/glTF-Sample-Assets/tree/main/Models/CarConcept)
by Eric Chadwick, © 2024 Darmstadt Graphics Group GmbH, based on a CC0 model by
Unity Fan. [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).
Logos and associated trademarks (Khronos) are excluded from the license.
The game binds the model to its soft-body simulation and deforms it at runtime.
