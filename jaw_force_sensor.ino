/*
  Jaw Force Challenge - load cell sketch (same sketch on every team's Uno R3)

  Hardware: load cell -> HX711 amplifier -> Elegoo/Arduino Uno R3
    HX711 VCC -> 5V      HX711 GND -> GND
    HX711 DT  -> pin 3   HX711 SCK -> pin 2
  Library:  "HX711 Arduino Library" by Bogdan Necula (Library Manager)

  Serial protocol @ 115200 baud, one message per line:
    Sends   F:<newtons>        calibrated force reading (~10 per second)
            R:<raw>            raw reading, sent only until the rig is calibrated
            OK:TARE / OK:CAL:<factor> / ERR:<why> / INFO:<status>
            ERR:NOHX711 if the HX711 stops answering (check the wiring);
            the sketch never waits forever, so it can't freeze.
    Accepts t                  zero the scale (jaw must be unloaded)
            c <grams>          calibrate using a known mass sitting on the load cell
            ?                  report status

  Calibration is saved in EEPROM, so each rig only needs calibrating once.
  The board zeroes itself on startup, which also happens every time the
  webpage connects, so keep the jaw unloaded while connecting.
*/

#include <HX711.h>
#include <EEPROM.h>

const int DOUT_PIN = 3;
const int SCK_PIN  = 2;
const float GRAMS_TO_NEWTONS = 0.00980665;
const uint32_t CAL_MAGIC = 0x4A415731;  // marks a valid saved calibration
const int CAL_ADDR = 0;

struct Calibration {
  uint32_t magic;
  float factor;
};

HX711 scale;
float factor = 1.0;
bool calibrated = false;
char cmd[24];
byte cmdLen = 0;
unsigned long lastReading = 0;   // millis() of the last good HX711 reading
unsigned long lastWarning = 0;

// Average n raw readings, giving up if the HX711 doesn't answer within
// 500 ms. Returns false instead of hanging when a wire is loose.
bool averageRaw(byte n, double &out) {
  double sum = 0;
  for (byte i = 0; i < n; i++) {
    if (!scale.wait_ready_timeout(500)) return false;
    sum += scale.read();
  }
  out = sum / n;
  lastReading = millis();
  return true;
}

// Zero the scale. Returns false if the HX711 isn't answering.
bool tareSafe(byte n) {
  double raw;
  if (!averageRaw(n, raw)) return false;
  scale.set_offset((long)raw);
  return true;
}

void noHX711() {
  Serial.println(F("ERR:NOHX711"));
  lastWarning = millis();
}

void setup() {
  Serial.begin(115200);
  scale.begin(DOUT_PIN, SCK_PIN);

  Calibration cal;
  EEPROM.get(CAL_ADDR, cal);
  if (cal.magic == CAL_MAGIC && !isnan(cal.factor) && fabs(cal.factor) > 1e-6) {
    factor = cal.factor;
    calibrated = true;
  }
  scale.set_scale(factor);

  delay(500);
  if (!tareSafe(20)) noHX711();
  Serial.println(calibrated ? F("INFO:ready") : F("INFO:not calibrated"));
}

void loop() {
  readCommands();

  if (!scale.is_ready()) {
    // No reading for 2 s: the HX711 has stopped answering. Say so every 3 s.
    if (millis() - lastReading > 2000 && millis() - lastWarning > 3000) noHX711();
    return;
  }
  lastReading = millis();
  // Send at most 20 readings a second. Some boards (like the UNO R4) can
  // send thousands a second, which floods the station page and freezes it.
  static unsigned long lastSent = 0;
  if (millis() - lastSent < 50) { scale.read(); return; }
  lastSent = millis();
  {
    if (calibrated) {
      float newtons = scale.get_units(1) * GRAMS_TO_NEWTONS;
      Serial.print(F("F:"));
      Serial.println(newtons, 2);
    } else {
      Serial.print(F("R:"));
      Serial.println((long)scale.get_value(1));
    }
  }
}

void readCommands() {
  while (Serial.available()) {
    char ch = Serial.read();
    if (ch == '\n' || ch == '\r') {
      if (cmdLen > 0) {
        cmd[cmdLen] = '\0';
        runCommand(cmd);
        cmdLen = 0;
      }
    } else if (cmdLen < sizeof(cmd) - 1) {
      cmd[cmdLen++] = ch;
    }
  }
}

void runCommand(const char *c) {
  if (c[0] == 't') {
    Serial.println(F("INFO:busy"));
    if (tareSafe(20)) Serial.println(F("OK:TARE"));
    else noHX711();
  } else if (c[0] == 'c') {
    float grams = atof(c + 1);
    if (grams <= 0) {
      Serial.println(F("ERR:enter a mass above 0 g"));
      return;
    }
    Serial.println(F("INFO:busy"));
    double raw;
    if (!averageRaw(20, raw)) { noHX711(); return; }
    double reading = raw - scale.get_offset();  // average minus tare offset
    float newFactor = reading / grams;
    if (fabs(newFactor) < 1e-6) {
      Serial.println(F("ERR:no load detected, check the mass and wiring"));
      return;
    }
    factor = newFactor;
    calibrated = true;
    scale.set_scale(factor);
    Calibration cal = { CAL_MAGIC, factor };
    EEPROM.put(CAL_ADDR, cal);
    Serial.print(F("OK:CAL:"));
    Serial.println(factor, 4);
  } else if (c[0] == '?') {
    Serial.print(F("INFO:"));
    Serial.print(calibrated ? F("calibrated factor=") : F("not calibrated factor="));
    Serial.println(factor, 4);
  } else {
    Serial.println(F("ERR:unknown command"));
  }
}
