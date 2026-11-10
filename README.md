# Jaw Force Challenge Leaderboard

A live classroom leaderboard for the McKibben-muscle jaw project. Each team's load cell sensor sends its readings to a web page, every squeeze of the jaw is saved automatically, and the results appear instantly on the projector.

Built by the Soft Robotics Clinic, Fall 2026: Chidera Anyanwu, Brandon De La Puente, Blanca Rivera, Kieran McGovern, Gabriella Pagano, David Weaver.

**Start here: [JAWS Project Guide](https://pagano770.github.io/Jaws-Leaderboard/guide.html)** (every tool, link and file on one page)

- **Scoreboard (projector):** https://pagano770.github.io/Jaws-Leaderboard/
- **Team station:** https://pagano770.github.io/Jaws-Leaderboard/#station
- **Force vs. pressure tool (muscle characterization):** https://pagano770.github.io/Jaws-Leaderboard/tools/force-pressure.html
- **Muscle pressure graph (pressure over time, leak rate):** https://pagano770.github.io/Jaws-Leaderboard/tools/muscle-pressure.html
- **Jaw force app (MATLAB Online):** [![Open in MATLAB Online](https://www.mathworks.com/images/responsive/global/open-in-matlab-online.svg)](https://matlab.mathworks.com/open/github/v1?repo=pagano770/Jaws-Leaderboard&file=jaw_force_app.m)

For a separate board per class period, add `?class=` to both links, for example `…/Jaws-Leaderboard/?class=s3` and `…/Jaws-Leaderboard/?class=s3#station`.

## What it does

- Reads the sensor directly in the browser. No software to install on the laptops.
- Saves each squeeze automatically. When the force passes the threshold (2 N by default), the page tracks the peak and saves it when the jaw lets go.
- Ranks teams three ways:
  - **Strongest bite:** each team's single best squeeze
  - **By orientation:** average force for every muscle orientation (A–G) and alternate jaw, plus a class average that shows which orientation works best
  - **Calculated vs. measured:** how close each team's moment-equation prediction came to the load cell
- Up to 10 teams, which can name themselves from the station page.
- Updates live on every screen through a free Firebase database.

## How it works

```
Load cell → HX711 amplifier → Arduino Uno ──USB──> Team station page (Chrome) ──> Firebase ──> Scoreboard
```

## Jaw force app (no MATLAB install needed)

`jaw_force_app.m` calculates each team's predicted jaw force: muscle force, torque, the moment balance, uncertainty, the best muscle angle, force vs. pressure, and the pressure calibration. It also imports the leaderboard's squeezes so teams can compare calculated and measured force.

To use it without installing anything:

1. Click the **Open in MATLAB Online** button above (it is also linked from the team station page).
2. Sign in with your Rowan account. Rowan's campus-wide MATLAB license covers MATLAB Online.
3. Choose to copy the repository into your MATLAB Drive when asked.
4. Type `jaw_force_app` in the Command Window and press Enter.

Each student gets their own copy, so changes and saved team files stay in their own MATLAB Drive. If you have desktop MATLAB (R2020b or newer), you can also download `jaw_force_app.m` and run it there.

## Files

| File | What it is |
|---|---|
| `index.html` | The whole website: scoreboard and team station in one page |
| `jaw_force_sensor.ino` | Arduino code, uploaded to every team's Uno. Keep it in a folder named `jaw_force_sensor` when opening it in the Arduino IDE |
| `jaw_force_app.m` | MATLAB app for calculating jaw force (see above) |
| `guide.html` | The project guide page: links to everything |
| `tools/force-pressure.html` | Muscle force vs. pressure graph and fit (Phase 1) |
| `arduino/muscle_force_pressure/` | Arduino logger for pressure and force together (Phase 1) |
| `tools/muscle-pressure.html` | Muscle pressure over time: peak and leak rate |
| `arduino/muscle_pressure_logger/` | MPRLS pressure recorder for the UNO R4 WiFi (prints DATA lines) |
| `database.rules.json` | Security rules to paste into Firebase |
| `SETUP.md` | Step-by-step setup and classroom instructions |
| `README.md` | This page |

## Muscle characterization (Phase 1)

To measure how much force the muscle makes at each pressure and length:

1. Upload `arduino/muscle_force_pressure/muscle_force_pressure.ino`. First set your HX711 pins, load cell factor (in newtons) and pressure-sensor calibration at the top.
2. In the Serial Monitor (115200 baud, "Newline"): `t` to zero, `c12` to set the contraction in mm, `h` at each syringe step, `n` for a new trial.
3. Paste the output into the [Force vs. pressure tool](https://pagano770.github.io/Jaws-Leaderboard/tools/force-pressure.html), which fits F = P(c₁ − c₂ε).

To check the muscle holds air, upload `arduino/muscle_pressure_logger/muscle_pressure_logger.ino` (UNO R4 WiFi + Adafruit MPRLS; install the "Adafruit MPRLS Library"), type `r`, push and hold the syringe, and paste the DATA line into the [Muscle pressure graph](https://pagano770.github.io/Jaws-Leaderboard/tools/muscle-pressure.html).

## Getting started

Full instructions are in [SETUP.md](SETUP.md). In summary:

1. Wire each load cell to an HX711 and Arduino Uno, and upload `jaw_force_sensor.ino`.
2. Create a free Firebase Realtime Database, paste in `database.rules.json`, and add the Firebase settings to the top of `index.html`.
3. Open the team station on each laptop, connect the sensor, and calibrate it once with a known mass.
4. Open the scoreboard on the projector and start testing.

Until the Firebase settings are added, the page works but results stay on the computer that recorded them, and the status shows **This computer only**.

## Requirements

- **Team stations:** Chrome or Edge on a laptop or desktop (needed to read the sensor over USB)
- **Scoreboard:** any modern browser, including phones
- **Jaw force app:** a web browser and a Rowan MathWorks sign-in (MATLAB Online), or desktop MATLAB R2020b or newer
- **Arduino library:** "HX711 Arduino Library" by Bogdan Necula
