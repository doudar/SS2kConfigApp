This branch is best tested as a reconnect/failover exercise, plus one short FIT export. The highest-value run takes about 30 minutes.

Before riding, use the SmartSpin2k `develop` firmware baseline and keep resistance low while deliberately dropping connections.

### Install and observe

Connect your phone by USB, then run:

```powershell
flutter pub get
flutter devices
flutter run -d <phone-device-id>
```

Expected: the app installs, opens the scan screen, and the terminal eventually reports the Dart VM service. Keep the terminal visible for `[DIRCON]`, `[AutoReconnect]`, and `[DIRCON][FALLBACK]` messages. Stop with `Ctrl+C` after testing.

The header indicates the active transport:

- Blue router: DIRCON
- Cellular-style signal bars: Bluetooth
- Red crossed-out signal: disconnected

### Core test sequence

1. **BLE workout**
   - Disable phone Wi-Fi before connecting, but leave Bluetooth enabled.
   - Connect and confirm signal bars.
   - Start a short steady ERG workout around 80–120 W.
   - Confirm cadence, power, and resistance update normally.
   - Run a ramp or manually change the target several times.
   - Pass: each target is applied once, promptly, without resistance surges.

2. **BLE reconnect**
   - Hold an unchanged, easy ERG target.
   - Power-cycle the SmartSpin2k.
   - Do not repeatedly press Connect.
   - Pass: the app reconnects automatically, metrics resume, and the same target is restored once. Resistance must not jump through old targets.

3. **Reconnect-sensitive screens**
   - Open **Virtual Shifter**, note the gear, then power-cycle again.
   - After reconnect, tap up or down once.
   - Pass: the displayed gear returns to the authoritative device value and one tap produces exactly one shift.
   - Visit **Settings**, **Power Table**, and **Workout** afterward.
   - Pass: no frozen spinner, crash, stale connection indicator, or duplicated setup activity.

4. **Log-stream reconnect**
   - Open **Maintenance → View Logs**.
   - Wait for “Log streaming is active” and new log entries.
   - Power-cycle the SmartSpin2k while leaving this screen open.
   - Pass: it may briefly show “Reconnecting…”, then returns to “Log streaming is active” and new messages continue. It must not remain stuck on “Activating log streaming…”.

5. **DIRCON workout**
   - Put the phone and SmartSpin2k on the same Wi-Fi, with Bluetooth also enabled.
   - Reconnect and confirm the blue router icon.
   - Repeat a steady target, a ramp, and a transition to zero watts/free ride.
   - Pass: target changes and live metrics behave the same as BLE.

6. **DIRCON → BLE fallback**
   - While riding a low-power interval over DIRCON, turn off phone Wi-Fi but leave Bluetooth enabled.
   - Expected terminal message: `[DIRCON][FALLBACK] BLE ready ... redelivering target.`
   - Pass:
     - Header changes from router to Bluetooth signal bars.
     - Workout remains running.
     - The current interval target is restored once.
     - Power and cadence resume.
     - No burst of old resistance commands occurs.
     - **View Logs** resumes streaming if it was open.

7. **FIT duration**
   - Record a short workout for a known elapsed time, such as 2–3 minutes.
   - End the workout and export/share the FIT file.
   - Import it into your normal activity service or FIT viewer.
   - Pass: lap, session, and total activity duration approximately match the in-app elapsed time—not zero or the planned workout length. Allow a second or two for record-boundary differences.

### What to record

For each failure, capture:

- BLE or DIRCON
- Header icon before and after
- Workout target before disconnect
- Actual resistance behavior
- Whether metrics and logs resumed
- Approximate reconnect time
- Relevant terminal output
- Exported FIT file, if duration is wrong

The repository’s full hardware acceptance matrix is documented in [universal_transport_remediation_plan.md](C:/git/ss2kconfigapp/docs/universal_transport_remediation_plan.md:106). The most important regression targets for this branch are the header indicator, Virtual Shifter refresh, log-stream recovery, and FIT duration.