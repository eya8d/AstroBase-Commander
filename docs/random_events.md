# Educational random events

## What is connected

The main scene now includes `EventDirector`. After each Sol's building/resource processing, it may announce one event. The announcement appears in the event briefing label and stays visible for the player until the next Sol. The default chance is 35 percent per event opportunity.

- **Dust storm:** cuts the solar panels' energy output using `power_output_multiplier` in `data/events.json`.
- **Oxygen leak:** removes the configured oxygen amount per affected Sol, up to the oxygen currently available.
- **Archived solar particle event:** emits the shared `EventBus.space_weather_warning` signal with archived DONKI and RadLab records.

The event JSON files contain the changeable event values and weights. No event balance amounts are embedded in the director script.

## Scene and files

```text
Main (Node2D) — scenes/main.tscn
├── EventDirector (Node) — scenes/event_director.tscn
└── UILayer (CanvasLayer)
    ├── DebugLabel (Label)
    └── EventLabel (Label)
```

- `scripts/event_director.gd` — event selection, event duration, and shared weather signals.
- `scripts/main_debug.gd` — applies the dust-storm and oxygen-leak effects during Sol processing and displays event briefings.
- `data/events.json` — authored dust-storm and oxygen-leak content and balance values.
- `data/nasa/solar_events.json` — archived NASA DONKI SEP event.
- `data/nasa/radiation.json` — NASA OSDR RadLab Mars surface dose-rate summaries associated with the September 2017 event.

## How to run it

Open the project at `AstroBase-Commander-main/project.godot` with Godot 4.6 Standard and run the main scene. The event director is already instanced. Press F3 to advance a Sol during manual checking. Event notices arrive after resource processing and remain active through the next Sol, giving the player a chance to change which buildings are powered.

Use E near the Shield Generator to toggle it. Its energy cost is shown by the existing building interaction text and is processed through the existing power budget.

## Archived NASA data

The archived DONKI SEP record is dated 6 September 2017. Its associated Mars surface event was observed 10–12 September 2017. RadLab's Curiosity MSL-RAD-Surface readings show daily mean absorbed dose rates of 7.68 microgray/hour on 6 September (83 readings) and 17.87 microgray/hour on 11 September (129 readings), approximately 2.3 times the comparison day's mean.

These are archived measurements, not live forecasts or crew health limits. DONKI identifies the solar particle event; RadLab provides actual Mars surface readings. The radiation event currently displays this evidence and prompts a Shield Generator power decision. The project does not yet have a crew-health resource or a validated habitat shielding model, so it does not convert these measurements into invented health damage or claim a specific dose reduction from the in-game generator.

NASA sources:

- DONKI event SEP 13081: <https://kauai.ccmc.gsfc.nasa.gov/DONKI/view/SEP/13081/1>
- NASA/JPL report of the September 2017 storm at Mars: <https://www.jpl.nasa.gov/news/large-solar-storm-sparks-global-aurora-and-doubles-radiation-levels-on-the-martian-surface/>
- RadLab data API: <https://visualization.osdr.nasa.gov/radlab/api/>
- RadLab dataset description for MSL-RAD-Surface: <https://visualization.osdr.nasa.gov/radlab/gui/knowledgebase/MSL-RAD-Surface>

Data retrieved on `2026-11-13`.

## Manual check list

1. Run the main scene — the game opens with the event briefing visible and no missing EventDirector node.
2. Advance Sols with F3 — an event appears occasionally; set `event_chance_percent` to 100 in the EventDirector Inspector to force one each opportunity while checking.
3. On a dust storm — solar panel energy output is reduced according to `data/events.json` for one Sol.
4. On an oxygen leak — oxygen decreases by the configured amount, capped at the current oxygen stock.
5. On the archived SEP warning — the briefing shows the event date, both RadLab daily means, units, NASA source, and the Shield Generator choice.
6. Toggle the Shield Generator with E — its normal energy cost changes the shared energy budget.
