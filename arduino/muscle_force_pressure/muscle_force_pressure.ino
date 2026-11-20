// JAWS Phase 1 — McKibben muscle force vs. pressure characterization
// Reads the 0–80 psi pressure sensor (A0) and the bar load cell (HX711) together.
//
// EASIEST: open the Muscle Characterization page in Chrome and click "Connect Arduino".
// The page has buttons for everything below (close the Arduino IDE Serial Monitor first).
//
// OR BY HAND (Serial Monitor: 115200 baud, line ending "Newline")
//   1. Muscle hanging, deflated, turnbuckle snug.  Type  t   to zero everything.
//   2. Set the turnbuckle to the contraction you want, then type it in mm:  c10
//   3. Type  s  to START. Slowly open the compressor/regulator up to your max
//      pressure, then slowly let it back down.
//   4. Type  s  again to STOP. You get a short summary.
//   5. Change the contraction (c15, c20, ...) and repeat 3–4.
//   6. Copy everything in the Serial Monitor and paste it into the
//      Muscle Characterization page. Only the STEP lines are used.
//
// Other commands:
//   n        new trial number (for repeats of the whole set)
//   h        one manual point: hold still, averages 2 s, prints one STEP line
//   l        live readings on/off (l1 = on, l0 = off)
//   f123.4   set the load cell factor (counts per newton) without re-uploading
//   ?        print settings
//
// Each STEP line: STEP,trial,contraction_mm,pressure_psi,force_N,pressure_sd_psi,force_sd_N

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

// ---------- recording ----------
const unsigned long REC_MS   = 250;   // one STEP point every 0.25 s while recording
const float MIN_PSI          = 0.3;   // ignore points below this (muscle not pressurized yet)
const float FORCE_LIMIT_N    = 40.0;  // 5 kg load cell: stop above this. Use 90 for a 10 kg cell.
const float PSI_LIMIT        = 60.0;  // stop above this pressure

// ---------- timing for manual points ----------
const unsigned long SAMPLE_MS = 100;
const unsigned long SETTLE_MS = 1000;
const unsigned long AVG_MS    = 2000;

HX711 scale;
float pZeroPsi = 0.0;
float contractionMm = 0.0;
int trial = 1;
bool live = false;
bool recording = false;
unsigned long lastSample = 0, recStart = 0, lastGoodForce = 0;
int missed = 0;   // load cell readings skipped during this recording
// running sums for the current 0.25 s recording window
float wP = 0, wP2 = 0, wF = 0, wF2 = 0; int wN = 0;
// summary of the current recording
int recPoints = 0; float recMaxP = 0, recMaxF = 0;

float readPsiRaw() {
  long sum = 0;
  for (int i = 0; i < 8; i++) sum += analogRead(P_PIN);   // 8x oversample to cut ADC noise
  float volts = (sum / 8.0) * VREF / 1023.0;
  float psi = (volts - 0.5) * 20.0;
  return P_GAIN * psi + P_OFFSET;
}
float readPsi() { return readPsiRaw() - pZeroPsi; }
float readForceN() {
  if (!scale.wait_ready_timeout(300)) return NAN;   // HX711 not answering: check 5V, GND, DT, SCK
  return FORCE_SIGN * scale.get_units(1);
}

void printSettings() {
  Serial.print(F("# trial ")); Serial.print(trial);
  Serial.print(F(" | contraction ")); Serial.print(contractionMm, 1);
  Serial.print(F(" mm | p zero ")); Serial.print(pZeroPsi, 3);
  Serial.print(F(" psi | LC factor ")); Serial.print(LC_FACTOR, 1);
  Serial.print(F(" | live ")); Serial.print(live ? F("on") : F("off"));
  Serial.print(F(" | recording ")); Serial.println(recording ? F("on") : F("off"));
}

void printStep(float mp, float mf, float sdp, float sdf) {
  Serial.print(F("STEP,")); Serial.print(trial);
  Serial.print(','); Serial.print(contractionMm, 1);
  Serial.print(','); Serial.print(mp, 3);
  Serial.print(','); Serial.print(mf, 3);
  Serial.print(','); Serial.print(sdp, 3);
  Serial.print(','); Serial.println(sdf, 3);
}

void tareAll() {
  if (recording) { Serial.println(F("# stop recording first (type s)")); return; }
  Serial.println(F("# zeroing: muscle deflated, nothing pulling..."));
  if (!scale.wait_ready_timeout(1000)) { Serial.println(F("# ERROR: no load cell. Check HX711 5V, GND, DT (pin 3), SCK (pin 2).")); return; }
  scale.tare(20);
  float s = 0;
  for (int i = 0; i < 20; i++) { s += readPsiRaw(); delay(20); }
  pZeroPsi = s / 20.0;
  Serial.println(F("# zeroed"));
  printSettings();
}

void resetWindow() { wP = wP2 = wF = wF2 = 0; wN = 0; }

void startRecording() {
  recording = true; live = false;
  recPoints = 0; recMaxP = 0; recMaxF = 0; missed = 0;
  resetWindow();
  recStart = lastSample = lastGoodForce = millis();
  Serial.print(F("# RECORDING trial ")); Serial.print(trial);
  Serial.print(F(" at ")); Serial.print(contractionMm, 1);
  Serial.println(F(" mm. Slowly raise the pressure, then slowly lower it. Type s to stop."));
}

void stopRecording(const __FlashStringHelper *why) {
  recording = false;
  Serial.print(F("# STOPPED")); if (why) { Serial.print(F(" (")); Serial.print(why); Serial.print(')'); }
  Serial.print(F(": ")); Serial.print(recPoints);
  Serial.print(F(" points in ")); Serial.print((millis() - recStart) / 1000.0, 1);
  Serial.print(F(" s, max ")); Serial.print(recMaxP, 1);
  Serial.print(F(" psi, max ")); Serial.print(recMaxF, 1); Serial.println(F(" N"));
  if (missed > 0) { Serial.print(F("# skipped ")); Serial.print(missed); Serial.println(F(" load cell readings (a few is fine; many = check the HX711 wires)")); }
  if (recPoints < 5 && !why) Serial.println(F("# Few points: was the muscle pressurized above 0.3 psi?"));
}

// called every loop while recording: sample ~10x per window, print one averaged point per window
void recordTick() {
  float p = readPsi(), f = readForceN();
  if (isnan(f)) {
    missed++;
    if (millis() - lastGoodForce > 2000) stopRecording(F("no load cell reading for 2 s: check HX711 5V, GND, DT pin 3, SCK pin 2"));
    return;   // skip this sample, keep recording
  }
  lastGoodForce = millis();
  wP += p; wP2 += p * p; wF += f; wF2 += f * f; wN++;

  if (f > FORCE_LIMIT_N) { stopRecording(F("FORCE LIMIT, let the pressure out now")); return; }
  if (p > PSI_LIMIT)     { stopRecording(F("PRESSURE LIMIT, let the pressure out now")); return; }

  if (millis() - lastSample >= REC_MS) {
    lastSample = millis();
    if (wN > 0) {
      float mp = wP / wN, mf = wF / wN;
      float vp = wP2 / wN - mp * mp; if (vp < 0) vp = 0;
      float vf = wF2 / wN - mf * mf; if (vf < 0) vf = 0;
      if (mp >= MIN_PSI) {
        printStep(mp, mf, sqrt(vp), sqrt(vf));
        recPoints++;
        if (mp > recMaxP) recMaxP = mp;
        if (mf > recMaxF) recMaxF = mf;
      }
    }
    resetWindow();
  }
}

void hold() {
  if (recording) { Serial.println(F("# stop recording first (type s)")); return; }
  Serial.print(F("# holding... keep the pressure steady"));
  unsigned long t0 = millis();
  while (millis() - t0 < SETTLE_MS) delay(5);
  float sp = 0, sp2 = 0, sf = 0, sf2 = 0; int n = 0;
  unsigned long t1 = millis();
  while (millis() - t1 < AVG_MS) {
    float p = readPsi(), f = readForceN();
    if (isnan(f)) { Serial.println(); Serial.println(F("# ERROR: load cell stopped answering")); return; }
    sp += p; sp2 += p * p; sf += f; sf2 += f * f; n++;
    delay(SAMPLE_MS);
  }
  float mp = sp / n, mf = sf / n;
  float vp = sp2 / n - mp * mp; if (vp < 0) vp = 0;
  float vf = sf2 / n - mf * mf; if (vf < 0) vf = 0;
  Serial.println();
  printStep(mp, mf, sqrt(vp), sqrt(vf));
}

void handle(String cmd) {
  cmd.trim();
  if (!cmd.length()) return;
  char c = cmd.charAt(0);
  if (c == 's') { if (recording) stopRecording(NULL); else startRecording(); }
  else if (recording) Serial.println(F("# recording: type s to stop first"));
  else if (c == 't') tareAll();
  else if (c == 'h') hold();
  else if (c == 'n') { trial++; printSettings(); }
  else if (c == 'c') { contractionMm = cmd.substring(1).toFloat(); printSettings(); }
  else if (c == 'l') { live = cmd.length() > 1 ? cmd.charAt(1) == '1' : !live; printSettings(); }
  else if (c == 'f') {
    float k = cmd.substring(1).toFloat();
    if (k != 0) { LC_FACTOR = k; scale.set_scale(LC_FACTOR); }
    printSettings();
  }
  else if (c == '?') printSettings();
  else Serial.println(F("# commands: t (zero)  c<mm>  s (start/stop)  n  h  l  f<factor>  ?"));
}

void setup() {
  Serial.begin(115200);
  unsigned long w = millis();
  while (!Serial && millis() - w < 3000) {}   // UNO R4: wait briefly for the Serial Monitor
  scale.begin(HX_DOUT, HX_SCK);
  scale.set_scale(LC_FACTOR);
  delay(500);
  Serial.println(F("# JAWS muscle force vs pressure logger"));
  Serial.println(F("# t = zero, c10 = set contraction (mm), s = start/stop recording"));
  tareAll();
}

void loop() {
  if (Serial.available()) handle(Serial.readStringUntil('\n'));
  if (recording) { recordTick(); return; }
  if (live && millis() - lastSample >= SAMPLE_MS) {
    lastSample = millis();
    float f = readForceN();
    Serial.print(F("LIVE,")); Serial.print(millis() / 1000.0, 2);
    Serial.print(','); Serial.print(readPsi(), 3);
    Serial.print(','); if (isnan(f)) Serial.println(F("no load cell")); else Serial.println(f, 3);
  }
}
