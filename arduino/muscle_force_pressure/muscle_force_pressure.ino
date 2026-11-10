// JAWS Phase 1 — McKibben muscle force vs. pressure characterization
// Logs the Walfront 0–80 psi transducer (A0) and the bar load cell (HX711) together.
//
// Serial Monitor: 115200 baud, line ending "Newline". Commands:
//   t        tare the load cell AND zero the pressure sensor (muscle deflated, no load)
//   c12.5    set the contraction being held, in mm (0 = full length). Measure it with the ruler.
//   n        start a new trial (trial number +1)
//   h        HOLD: wait 1 s to settle, average the next 2 s, print one STEP line
//   l        turn the live stream (LIVE lines, 10 per second) on/off
//   ?        print settings
//
// Copy every line that starts with STEP into the Force vs. Pressure page.
// STEP,trial,contraction_mm,pressure_psi,force_N,pressure_sd_psi,force_sd_N

#include "HX711.h"   // Library Manager: "HX711 Arduino Library" by Bogdan Necula

// ---------- wiring ----------
const int HX_DOUT = 3;
const int HX_SCK  = 2;
const int P_PIN   = A0;

// ---------- calibration: put YOUR numbers here ----------
float LC_FACTOR  = -7050.0;   // HX711 counts per newton from your hanging-mass calibration
const float FORCE_SIGN = 1.0; // set to -1.0 if force reads negative when the muscle pulls

// Sensor: 0.5 V = 0 psi, 4.5 V = 80 psi  ->  20 psi per volt
const float VREF = 5.0;       // measure the Arduino 5 V pin with a multimeter and type it here
// Tire-gauge check: true_psi = P_GAIN * sensor_psi + P_OFFSET (fit a line from 3–4 pressures)
const float P_GAIN   = 1.000;
const float P_OFFSET = 0.000;

// ---------- timing ----------
const unsigned long SAMPLE_MS = 100;   // 10 Hz
const unsigned long SETTLE_MS = 1000;  // ignore the first 1 s of a hold
const unsigned long AVG_MS    = 2000;  // then average 2 s

HX711 scale;
float pZeroPsi = 0.0;
float contractionMm = 0.0;
int trial = 1;
bool live = false;
unsigned long lastSample = 0;

float readPsiRaw() {
  long sum = 0;
  for (int i = 0; i < 8; i++) sum += analogRead(P_PIN);   // 8x oversample to cut ADC noise
  float volts = (sum / 8.0) * VREF / 1023.0;
  float psi = (volts - 0.5) * 20.0;
  return P_GAIN * psi + P_OFFSET;
}
float readPsi() { return readPsiRaw() - pZeroPsi; }
float readForceN() { return FORCE_SIGN * scale.get_units(1); }

void printSettings() {
  Serial.print(F("# trial ")); Serial.print(trial);
  Serial.print(F(" | contraction ")); Serial.print(contractionMm, 1);
  Serial.print(F(" mm | p zero ")); Serial.print(pZeroPsi, 3);
  Serial.print(F(" psi | LC factor ")); Serial.print(LC_FACTOR, 1);
  Serial.print(F(" | live ")); Serial.println(live ? F("on") : F("off"));
}

void tareAll() {
  Serial.println(F("# taring: muscle deflated, nothing pulling..."));
  scale.tare(20);
  float s = 0;
  for (int i = 0; i < 20; i++) { s += readPsiRaw(); delay(20); }
  pZeroPsi = s / 20.0;
  Serial.println(F("# tared"));
  printSettings();
}

void hold() {
  Serial.print(F("# holding... keep the syringe still"));
  unsigned long t0 = millis();
  while (millis() - t0 < SETTLE_MS) delay(5);
  float sp = 0, sp2 = 0, sf = 0, sf2 = 0; int n = 0;
  unsigned long t1 = millis();
  while (millis() - t1 < AVG_MS) {
    float p = readPsi(), f = readForceN();
    sp += p; sp2 += p * p; sf += f; sf2 += f * f; n++;
    delay(SAMPLE_MS);
  }
  float mp = sp / n, mf = sf / n;
  float vp = sp2 / n - mp * mp; if (vp < 0) vp = 0;
  float vf = sf2 / n - mf * mf; if (vf < 0) vf = 0;
  float sdp = sqrt(vp), sdf = sqrt(vf);
  Serial.println();
  Serial.print(F("STEP,")); Serial.print(trial);
  Serial.print(','); Serial.print(contractionMm, 1);
  Serial.print(','); Serial.print(mp, 3);
  Serial.print(','); Serial.print(mf, 3);
  Serial.print(','); Serial.print(sdp, 3);
  Serial.print(','); Serial.println(sdf, 3);
}

void handle(String cmd) {
  cmd.trim();
  if (!cmd.length()) return;
  char c = cmd.charAt(0);
  if (c == 't') tareAll();
  else if (c == 'h') hold();
  else if (c == 'n') { trial++; printSettings(); }
  else if (c == 'c') { contractionMm = cmd.substring(1).toFloat(); printSettings(); }
  else if (c == 'l') { live = !live; printSettings(); }
  else if (c == '?') printSettings();
  else Serial.println(F("# commands: t  c<mm>  n  h  l  ?"));
}

void setup() {
  Serial.begin(115200);
  scale.begin(HX_DOUT, HX_SCK);
  scale.set_scale(LC_FACTOR);
  delay(500);
  Serial.println(F("# JAWS muscle force vs pressure logger"));
  tareAll();
}

void loop() {
  if (Serial.available()) handle(Serial.readStringUntil('\n'));
  if (live && millis() - lastSample >= SAMPLE_MS) {
    lastSample = millis();
    Serial.print(F("LIVE,")); Serial.print(millis() / 1000.0, 2);
    Serial.print(','); Serial.print(readPsi(), 3);
    Serial.print(','); Serial.println(readForceN(), 3);
  }
}
