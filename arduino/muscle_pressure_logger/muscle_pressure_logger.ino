/*
 * Pressure sensor test + recorder
 * Walfront 0-80 psi, 0.5-4.5 V output
 * Wiring: red -> 5V, black -> GND, signal wire -> A0
 *
 * Open the Serial Monitor at 9600 baud. It shows live readings.
 *
 * RECORD A TEST:
 *   Type r and press Enter, then push/hold/release the syringe.
 *   After 20 seconds it prints the peak pressure and ONE line that
 *   starts with DATA. Copy just that one line.
 *
 * RUN ANOTHER TEST: type r and press Enter again, as many times as
 *   you like. Each test is numbered. Typing r in the middle of a
 *   test throws that test away and starts a fresh one.
 *
 * Other commands: t = re-zero (nothing pushing on the sensor),
 *                 p = back to live readings.
 * Capital letters (R, T, P) work too.
 */

const int PRESSURE_PIN = A0;
const float P_MAX_KPA = 551.6;      // 80 psi
const float KPA_PER_PSI = 6.895;
const float RECORD_SECONDS = 20.0;  // length of one recorded test
const int   MAX_SAMPLES = 260;      // room for 20 s at ~10 readings/s

float zeroV = 0.5;

bool recording = false;
bool finished = false;
unsigned long recordStart = 0;
unsigned long lastCountdown = 0;
float samples[MAX_SAMPLES];         // stored in psi
int sampleCount = 0;
int testNumber = 0;

float readVolts() {
  long sum = 0;
  for (int i = 0; i < 20; i++) sum += analogRead(PRESSURE_PIN);
  return (sum / 20.0) * 5.0 / 1023.0;
}

void zeroSensor() {
  zeroV = readVolts();              // nothing pushing on the sensor
  Serial.print(F("Zero voltage: "));
  Serial.println(zeroV, 3);
}

void startTest() {
  testNumber++;
  recording = true;
  finished = false;
  sampleCount = 0;
  lastCountdown = 0;
  Serial.println();
  Serial.print(F("TEST "));
  Serial.print(testNumber);
  Serial.println(F(": RECORDING for 20 seconds - push the syringe now!"));
  recordStart = millis();
}

void printResults(float elapsed) {
  float interval = (sampleCount > 1) ? elapsed / sampleCount : 0.1;
  int peakIndex = 0;
  for (int i = 1; i < sampleCount; i++) {
    if (samples[i] > samples[peakIndex]) peakIndex = i;
  }

  Serial.println();
  Serial.print(F("===== TEST "));
  Serial.print(testNumber);
  Serial.println(F(" DONE ====="));
  Serial.print(F("Peak pressure: "));
  Serial.print(samples[peakIndex] * KPA_PER_PSI, 1);
  Serial.print(F(" kPa ("));
  Serial.print(samples[peakIndex], 2);
  Serial.print(F(" psi) at "));
  Serial.print(peakIndex * interval, 1);
  Serial.println(F(" seconds"));
  Serial.println(F("Copy the ONE line below that starts with DATA:"));

  // DATA,<seconds between readings>,<reading 1 in psi>,<reading 2 in psi>,...
  Serial.print(F("DATA,"));
  Serial.print(interval, 3);
  for (int i = 0; i < sampleCount; i++) {
    Serial.print(',');
    Serial.print(samples[i], 2);
  }
  Serial.println();
  Serial.println();
  Serial.println(F(">>> Type r + Enter to run another test, t to re-zero, p for live readings."));
}

void handleCommand(char c) {
  if (c == 'r' || c == 'R') {
    startTest();
  } else if (c == 't' || c == 'T') {
    if (recording) {
      Serial.println(F("Can't re-zero during a test - wait until it finishes."));
    } else {
      zeroSensor();
    }
  } else if (c == 'p' || c == 'P') {
    recording = false;
    finished = false;
  }
  // anything else (Enter, spaces, other letters) is ignored
}

void setup() {
  Serial.begin(9600);
  delay(500);
  zeroSensor();                     // nothing pushing on the sensor at startup
  Serial.println(F("Type r + Enter to record a 20 second test."));
}

void loop() {
  while (Serial.available()) {
    handleCommand(Serial.read());
  }

  float v = readVolts();
  float kPa = (v - zeroV) / 4.0 * P_MAX_KPA;
  float psi = kPa / KPA_PER_PSI;

  if (recording) {
    float elapsed = (millis() - recordStart) / 1000.0;
    if (sampleCount < MAX_SAMPLES) samples[sampleCount++] = psi;

    // One short status line per second so you can see it working
    if (millis() - lastCountdown >= 1000) {
      lastCountdown = millis();
      Serial.print(F("  "));
      Serial.print((int)(RECORD_SECONDS - elapsed + 0.5));
      Serial.print(F(" s left   pressure now: "));
      Serial.print(kPa, 1);
      Serial.print(F(" kPa ("));
      Serial.print(psi, 2);
      Serial.println(F("
