# Audio Assets and Sources

Downloaded source assets, wired into `scripts/audio_manager.gd`. 30 files, 26.2 MB total.
Two sets: the pack assembled earlier by the assistant, and the set collected by the user in
`D:\Downloads\المهم\المهم` (source folders are named by role in Arabic).

## Original pack

| File | Use | Source and license |
|---|---|---|
| `music/menu_space_music.ogg` | Main menu space ambience | [Space Music: Out There](https://opengameart.org/content/space-music-out-there), yd, CC0. |
| `music/disaster_high_alert.ogg` | Disaster / emergency music | [High Alert](https://opengameart.org/content/high-alert), section31, CC0. |
| `ambience/mars_perseverance_wind_sol04.mp3` | Mars atmosphere reference ambience | [Perseverance SuperCam wind recording](https://science.nasa.gov/resource/perseverance-rovers-supercam-records-wind-on-mars/), credit: NASA/JPL-Caltech/LANL/CNES/CNRS/ISAE-Supaero. Follow [NASA media-use guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/); do not imply NASA endorsement. |
| `sfx/dust_storm_wind_loop.ogg` | Loopable storm wind | [wind whoosh loop](https://opengameart.org/content/wind-whoosh-loop), SketchMan3, CC0. |
| `sfx/oxygen_leak.ogg` | Loopable gas leak | [Compressed Gas Leak SFX](https://opengameart.org/content/compressed-gas-leak-sfx), 0new4y, CC0. |
| `sfx/radiation_warning_alarm.ogg` | Radiation / emergency warning | [Alarm](https://opengameart.org/content/alarm-1), EZduzziteh, CC0. |
| `sfx/shield_protection_hum.wav` | Shield activation / protection | [Force field electric hum](https://opengameart.org/content/force-field-electric-hum), Hansjörg Malthaner. The source page offers CC-BY and CC-BY-SA variants; credit the author and link to [Varkalandar's profile](https://opengameart.org/users/varkalandar). |
| `sfx/sol_end_chime.wav` | Sol/day-end chime | [Bell Arpeggio 24](https://opengameart.org/content/bell-arpeggio-24), cynicmusic, CC0. Optional attribution: The Cynic Project / cynicmusic.com / pixelsphere.org. |
| `ui/ui_click_01.mp3` | UI click (also hover / confirm / back / error fallback) | [UI Click Sounds (Sci Fi)](https://opengameart.org/content/ui-click-sounds-sci-fi), EZduzziteh, CC0. |

## User-provided set (source folder role in Arabic)

| File | Role folder | Use in game | Source and license |
|---|---|---|---|
| `sfx/footstep_walk.wav` | مشي (walking) | Looping footsteps while the astronaut moves (`AudioManager.set_footsteps`) | Supplied by the user as `Walking Sound.wav`. Provenance/license not stated on the file - confirm before publishing. |
| `sfx/item_pickup.mp3` | mining / general | Picking up a generic item | Supplied by the user as `Item Pickup.mp3`. Provenance/license not stated - confirm before publishing. |
| `sfx/ore_crack.mp3` | التعدين (mining) | Ore node collected after mining | Supplied by the user as `Cracking Sound.mp3`. Provenance/license not stated - confirm before publishing. |
| `sfx/research_scan.mp3` | السرش (research) | Unlocking a NASA fact / opening data | [Freesound 304685](https://freesound.org/s/304685/) by `jci21`. Check the sound page for its license (CC0 or CC-BY 4.0); credit if CC-BY. |
| `sfx/switch_on.mp3` | السوتش (light switch) | Switching a structure ON | [Freesound 382712](https://freesound.org/s/382712/) by `dragon-studio`. Check the sound page for its license; credit if CC-BY. |
| `sfx/switch_off.mp3` | السوتش (light switch) | Switching a structure OFF | [Freesound 33745](https://freesound.org/s/33745/) via `freesound_community`. Check the sound page for its license; credit if CC-BY. |
| `sfx/warning_alert.mp3` | انضار (alarms) | Generic alert, failed mission, notices | [Freesound 29632](https://freesound.org/s/29632/) via `freesound_community` (sci-fi warning alert). Check the sound page for its license; credit if CC-BY. |
| `sfx/power_shortage_alarm.wav` | انضار (alarms) | Power budget goes negative | Supplied by the user as `sfx_power_shortage_alarm.wav`. Provenance/license not stated - confirm before publishing. |
| `sfx/demolish_bricks.mp3` | تكسير المبنا (breaking the building) | Reserved for a demolish action (`AudioManager.play_demolish`); no demolish feature exists yet | Supplied by the user as `Bricks breaking sound effect.mp3`. Provenance/license not stated - confirm before publishing. |
| `sfx/solar_cleaning.mp3` | تنضيف (cleaning) | Cleaning dust off a solar panel | Supplied by the user as `Solar Panel Cleaning Sound.mp3`. Provenance/license not stated - confirm before publishing. |
| `sfx/breathing_mask.mp3` | تنفس (breathing) | Looping gas-mask breathing while oxygen is critical | [Freesound 69348](https://freesound.org/s/69348/) via `freesound_community` (gas mask breath). Check the sound page for its license; credit if CC-BY. |
| `sfx/mask_breath_short.mp3` | تنفس (breathing) | Short single breath accent | [Freesound 73978](https://freesound.org/s/73978/) by `046709` via `freesound_community`. Check the sound page for its license; credit if CC-BY. |
| `sfx/water_pump_loop.mp3` | جهاز استخراج الميه او مضخه الاكسجين | Loop while a Water Extractor is ON | [Freesound 375793](https://freesound.org/s/375793/) by `robmoscreative`. Check the sound page for its license; credit if CC-BY. |
| `sfx/oxygen_generator_loop.wav` | جهاز استخراج الميه او مضخه الاكسجين | Loop while an Oxygen Generator is ON | Supplied by the user as `sfx_oxygen_generator_loop.wav`. Provenance/license not stated - confirm before publishing. |
| `sfx/construction_build.wav` | صوت البناء (construction) | Placing a building | [Mixkit - Cutting trees with chainsaw ambiance and axe hits](https://mixkit.co/free-sound-effects/construction/), Mixkit license (free, no attribution required). |
| `ui/ui_back.wav` | انضار (alarms) | Closing a panel | Supplied by the user as `back_0111.wav`. Provenance/license not stated - confirm before publishing. |
| `ui/ui_error.wav` | انضار (alarms) | Blocked action (not enough resources) | Supplied by the user as `error_01222.wav`. Provenance/license not stated - confirm before publishing. |
| `ui/mission_confirm.wav` | قيمه المهام (mission values) | Confirming a mission / results screen | Mixkit sci-fi confirmation, Mixkit license (free, no attribution required). |
| `ui/interface_zoom.wav` | قيمه المهام (mission values) | Focusing a card in the build menu | Mixkit sci-fi interface zoom, Mixkit license (free, no attribution required). |
| `ui/water_bleep.wav` | قيمه المهام (mission values) | Collecting water | Mixkit water sci-fi bleep, Mixkit license (free, no attribution required). |

Header note: `ui/mission_confirm.wav` and `ui/water_bleep.wav` arrived as 24-bit
`WAVE_FORMAT_EXTENSIBLE` files that the Godot WAV loader rejects
("Format not supported for WAVE file (not PCM)"). They were rewritten as classic
16-bit PCM files by `.work/scripts/fix_wav_header.ps1`; the originals are kept in
`.work/audio_src_backup`.

The role folder `تطوير المبنا` (building upgrade) is empty, so no upgrade sound exists yet.
