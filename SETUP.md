# Jaw Force Challenge leaderboard: setup guide

There are three parts. Each Arduino reads its load cell and sends force in newtons over USB. Each team's laptop runs the **team station** page in Chrome, which spots each squeeze and saves its peak. Everyone else watches the **scoreboard** page, which updates live from a free Firebase database.

```
Load cell → HX711 → Uno R3 ──USB──> Team laptop (Chrome, station page) ──> Firebase ──> Projector + phones (scoreboard)
```

## 1. Arduino rigs (repeat for all five)

1. Wire the HX711: VCC → 5V, GND → GND, DT → pin 3, SCK → pin 2. Load cell to HX711, usually red → E+, black → E−, white → A−, green → A+. If readings go negative when you squeeze, that's fine; calibration fixes the sign.
2. In the Arduino IDE, open Library Manager and install **HX711 Arduino Library** by Bogdan Necula.
3. Open `jaw_force_sensor/jaw_force_sensor.ino` and upload it. If your wiring uses different pins, change `DOUT_PIN` and `SCK_PIN` at the top.
4. Elegoo boards use a CH340 USB chip. If the board doesn't show up as a port, install the CH340 driver for your OS.

Calibration happens from the webpage (step 4), so every rig runs the identical sketch.

## 2. Firebase (free, about 10 minutes)

1. Go to console.firebase.google.com and create a project. You can skip Google Analytics.
2. Open **Build → Realtime Database → Create database**. Pick the US location and start in **locked mode**.
3. On the database's **Rules** tab, paste in everything from `database.rules.json` and publish.
4. Go to **Project settings → General → Your apps**, add a Web app (the `</>` icon) and copy the `firebaseConfig` object.
5. In `index.html`, near the top, replace `firebase: null` with that config. Make sure it includes `databaseURL`. If it's missing, copy the URL shown at the top of the Realtime Database page.

The free plan allows 100 devices connected at once, which is plenty for five stations, a projector and a class of phones.

**About security:** the web config is not a secret, and anyone with the link can add squeezes. The rules only allow well-formed force data. For a class this is usually fine, and you can delete bad entries from the admin view (step 5).

## 3. Host on GitHub Pages

1. Create a new public repository on GitHub and upload `index.html` to it.
2. Go to **Settings → Pages**, set the source to the `main` branch and root folder, and save.
3. After a minute your site is at `https://YOUR-USERNAME.github.io/REPO-NAME/`.

Web Serial requires HTTPS, and GitHub Pages provides it automatically.

## 4. Class day

| Who | Opens |
|---|---|
| Projector | `https://…/` (scoreboard) |
| Students' phones | same link |
| Each team laptop (Chrome or Edge) | `https://…/?station` |

At each station:

1. Choose your team slot.
2. With the jaw unloaded, click **Connect sensor** and pick the Arduino's port. The board restarts and zeroes itself.
3. **First time only:** open **Calibrate this rig**, press **Zero**, rest a known mass (e.g., a 500 g weight) on the load cell, type its mass in grams, and press **Calibrate**. The Arduino saves this permanently.
4. Optionally type a team name and click out of the box to save it.
5. Pick the orientation (A–G) or alternate jaw being tested, and enter your team's calculated force for it.
6. Squeeze. Any squeeze that goes above the threshold (default 2 N) saves its peak automatically. Use **Pause saving** for practice or setup, and **Delete** to remove a bad reading.

Only one program can use the serial port at a time, so close the Arduino Serial Monitor before connecting.

## 5. Extras

- **Separate class periods:** add `?class=p3` to both links (e.g., `…/?class=p3` and `…/?class=p3&station`). Each period gets its own board.
- **Admin view:** `…/?admin=1` adds delete buttons to the "Latest squeezes" feed and a button to clear the whole class, including team names.
- **Teams:** there are 10 team slots. Teams pick a slot and can rename themselves on the station page; the new name shows everywhere. Teams with no squeezes don't appear on the scoreboard, so unused slots stay hidden. To change the default slot names, jaw orientations or alternate jaw names, edit `teams`, `orientations` and `altJaws` in the `CONFIG` block at the top of `index.html`.
- **Demo mode:** leave `firebase: null`. The page fills itself with six fake teams and fake forces, adds a new simulated squeeze every few seconds (untick **Simulate live squeezes** to stop), and the station page gets a **Simulate a squeeze** button that runs a fake squeeze through the real detection code. Data stays in that browser only. **Reset demo data** starts over.
- **Switching views:** the link at the top right flips between scoreboard and station. You can also add `#station` to the end of the address.

## Troubleshooting

- **"Not calibrated yet":** run the calibration in step 4.
- **Readings drift while idle:** press **Zero** with the jaw unloaded.
- **Squeezes aren't saving:** check that a team is selected, saving isn't paused, and the force passes the threshold. Lower the threshold if your jaw produces small forces.
- **Scoreboard says "Reconnecting":** the device lost internet. It catches up automatically when it reconnects.
