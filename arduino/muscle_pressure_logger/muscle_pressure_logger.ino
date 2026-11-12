/*
 * McKibben muscle pressure logger
 * MPRLS sensor -> Arduino UNO R4 WiFi
 *
 * LIVE GRAPH: open Tools > Serial Plotter.
 *   Muscle_Pressure_PSI = pressure the syringe adds (0 = muscle at rest)
 *   Sensor_OK = 1 means the sensor is found, 0 means check wiring
 *
 * RECORD A TEST (Serial Monitor):
 *   Type r and press Enter, then push/hold/release the syringe.
 *   After 20 seconds it prints the peak pressure and ONE line that
 *   starts with DATA. Copy just that one line and paste it into the
 *   Muscle Pressure Graph page.
 *
 * Other commands: t = re-zero (syringe untouched), p = back to plotter.
 */

#include <Wire.h>
#include "Adafruit_MPRLS.h"

#define RESET_PIN  -1
#define EOC_PIN    -1
Adafruit_MPRLS mpr = Adafruit_MPRLS(RESET_PIN, EOC_PIN);

const float HPA_TO_PSI = 1.0 / 68.947572932;
const float MAX_GAUGE_PSI = 9.0;    // stay below this to protect the sensor
const float RECORD_SECONDS = 20.0;  // length of one recorded test
const int   MAX_SAMPLES = 260;      // room for 20 s at ~10 readings/s

bool sensorOK = false;
float baseline_hPa = 0;

bool recording = false;
bool finished = false;
unsigned long recordStart = 0;
unsigned long lastCountdown = 0;
float samples[MAX_SAMPLES];
int sampleCount = 0;

void tare() {
  float sum = 0;
  int good = 0;
  for (int i = 0; i < 30; i++) {
    float p = mpr.readPressure();
    if (!isnan(p)) { sum += p; good++; }
    delay(10);
  }
  if (good > 0) baseline_hPa = sum / good;
}

void trySensor() {
  sensorOK = mpr.begin();
  if (sensorOK) tare();
}

void printResults(float elapsed) {
  float interval = (sampleCount > 1) ? elapsed / sampleCount : 0.1;
  int peakIndex = 0;
  for (int i = 1; i < sampleCount; i++) {
    if (samples[i] > samples[peakIndex]) peakIndex = i;
  }

  Serial.println();
  Serial.println("===== TEST DONE =====");
  Serial.print("Peak pressure: ");
  Serial.print(samples[peakIndex], 2);
  Serial.print(" PSI at ");
  Serial.print(peakIndex * interval, 1);
  Serial.println(" seconds");
  Serial.println("Copy the ONE line below that starts with DATA:");

  // DATA,<seconds between readings>,<reading 1>,<reading 2>,...
  Serial.print("DATA,");
  Serial.print(interval, 3);
  for (int i = 0; i < sampleCount; i++) {
    Serial.print(",");
    Serial.print(samples[i], 2);
  }
  Serial.println();
  Serial.println("Type r to record another test, or p for the live plotter.");
}

void setup() {
  Serial.begin(115200);
  delay(1500);          // give the USB connection time to start
  trySensor();
}

void loop() {
  if (Serial.available()) {
    char c = Serial.read();
    if (c == 't' && sensorOK) tare();
    if (c == 'r') {
      recording = true;
      finished = false;
      sampleCount = 0;
      recordStart = millis();
      lastCountdown = 0;
      Serial.println();
      Serial.println("RECORDING for 20 seconds - push the syringe now!");
    }
    if (c == 'p') { recording = false; finished = false; }
  }

  float gauge_psi = 0;
  if (!sensorOK) {
    trySensor();        // keep retrying until the sensor is found
  } else {
    float p = mpr.readPressure();
    if (isnan(p)) sensorOK = false;
    else gauge_psi = (p - baseline_hPa) * HPA_TO_PSI;
  }

  if (recording) {
    float elapsed = (millis() - recordStart) / 1000.0;
    if (sampleCount < MAX_SAMPLES) samples[sampleCount++] = gauge_psi;

    // One short status line per second so you can see it working
    if (millis() - lastCountdown >= 1000) {
      lastCountdown = millis();
      Serial.print("  ");
      Serial.print((int)(RECORD_SECONDS - elapsed + 0.5));
      Serial.print(" s left   pressure now: ");
      Serial.print(gauge_psi, 2);
      Serial.println(" PSI");
    }

    if (elapsed >= RECORD_SECONDS || sampleCount >= MAX_SAMPLES) {
      recording = false;
      finished = true;
      printResults(elapsed);
    }
  } else if (!finished) {
    // Live plotter format
    Serial.print("Muscle_Pressure_PSI:");
    Serial.print(gauge_psi, 3);
    Serial.print(",Sensor_OK:");
    Serial.print(sensorOK ? 1 : 0);
    Serial.print(",Sensor_Limit:");
    Serial.println(MAX_GAUGE_PSI);
  }

  delay(75);
}
