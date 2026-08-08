// FTMS Control Point Op Codes
class FTMSOpCodes {
  // Control and General Settings
  static const int REQUEST_CONTROL = 0x00;
  static const int RESET = 0x01;

  // Workout Parameters
  static const int SET_TARGET_SPEED = 0x02;
  static const int SET_TARGET_INCLINATION = 0x03;
  static const int SET_TARGET_RESISTANCE_LEVEL = 0x04;
  static const int SET_TARGET_POWER = 0x05;
  static const int SET_TARGET_HEART_RATE = 0x06;
  static const int SET_TARGET_CADENCE = 0x14;
  static const int SET_INDOOR_BIKE_SIMULATION = 0x11;
  static const int SPIN_DOWN_CONTROL = 0x13;

  // Session Control
  static const int START_OR_RESUME = 0x07;
  static const int STOP_OR_PAUSE = 0x08;

  // Response Code
  static const int RESPONSE_CODE = 0x80;
}

// FTMS Response Result Codes
class FTMSResultCodes {
  static const int SUCCESS = 0x01;
  static const int OP_CODE_NOT_SUPPORTED = 0x02;
  static const int INVALID_PARAMETER = 0x03;
  static const int OPERATION_FAILED = 0x04;
  static const int CONTROL_NOT_PERMITTED = 0x05;
}

// FTMS Stop/Pause Parameters
class FTMSStopPauseParams {
  static const int STOP = 0x01;
  static const int PAUSE = 0x02;
}

// FTMS Spin Down Control Parameters
class FTMSSpinDownParams {
  static const int START = 0x01;
  static const int IGNORE = 0x02;
}

// FTMS Characteristic UUIDs
const String FTMS_CONTROL_POINT_CHARACTERISTIC_UUID = '00002AD9-0000-1000-8000-00805F9B34FB';
const String FTMS_MACHINE_STATUS_CHARACTERISTIC_UUID = '00002ADA-0000-1000-8000-00805F9B34FB';

// FTMS Machine Status Op Codes (first byte of a 0x2ADA notification)
class FTMSStatusOpCodes {
  static const int SPIN_DOWN_STATUS = 0x14;
}

/// Parameter byte of a [FTMSStatusOpCodes.SPIN_DOWN_STATUS] notification.
///
/// These names come from the FTMS specification and describe nothing the
/// SmartSpin2k actually does — the firmware reuses the codes as homing progress
/// markers. [MAX_SEARCH_STARTED] in particular does not ask the rider to stop;
/// pedalling has no effect on homing once the cadence gate has opened. What
/// carries the information is where in `Stepper.cpp` `goHome()` each byte is
/// emitted, so they are named for that position rather than for the spec label.
class FTMSSpinDownStatus {
  /// Emitted both when the command is accepted and at the top of `goHome()`.
  static const int SPIN_DOWN_REQUESTED = 0x01;

  /// Spec name `Success`. Stepper.cpp:506, and :392 on the resistance path.
  static const int SUCCESS = 0x02;

  /// Spec name `Error`. Stepper.cpp:399, :478 and :493 — every failure return.
  static const int ERROR = 0x03;

  /// Spec name `StopPedaling`. Stepper.cpp:489, the statement immediately after
  /// the min end stop is set, then repeated through the max search (:272 on the
  /// stepper path, :330 on the resistance sweep). The firmware only ever emits
  /// it from inside the max search, so receiving it proves min is behind us.
  static const int MAX_SEARCH_STARTED = 0x04;
}

// FTMS Data Lengths and Resolutions
class FTMSDataConfig {
  // Data Lengths
  static const int TARGET_POWER_LENGTH = 3;  // 1 byte opcode + 2 bytes power value
  static const int TARGET_SPEED_LENGTH = 3;  // 1 byte opcode + 2 bytes speed value
  static const int TARGET_INCLINATION_LENGTH = 3;  // 1 byte opcode + 2 bytes inclination value
  static const int TARGET_RESISTANCE_LENGTH = 2;  // 1 byte opcode + 1 byte resistance value
  static const int TARGET_HEART_RATE_LENGTH = 2;  // 1 byte opcode + 1 byte heart rate value
  static const int TARGET_CADENCE_LENGTH = 3;  // 1 byte opcode + 2 bytes cadence value
  static const int STOP_PAUSE_LENGTH = 2;  // 1 byte opcode + 1 byte stop/pause parameter
  static const int INDOOR_BIKE_SIMULATION_LENGTH = 7;  // 1 byte opcode + 2 bytes wind speed + 2 bytes grade + 1 byte Crr + 1 byte Cw
  static const int SPIN_DOWN_CONTROL_LENGTH = 2;  // 1 byte opcode + 1 byte control parameter

  // Data Resolutions
  static const double SPEED_RESOLUTION = 0.01;  // km/h
  static const double INCLINATION_RESOLUTION = 0.1;  // percentage
  static const double RESISTANCE_RESOLUTION = 0.1;  // unitless
  static const double POWER_RESOLUTION = 1.0;  // watts
  static const double HEART_RATE_RESOLUTION = 1.0;  // BPM
  static const double CADENCE_RESOLUTION = 0.5;  // 1/minute
  
  // Indoor Bike Simulation Resolutions
  static const double WIND_SPEED_RESOLUTION = 0.001;  // meters per second
  static const double GRADE_RESOLUTION = 0.01;  // percentage
  static const double CRR_RESOLUTION = 0.0001;  // unitless
  static const double CW_RESOLUTION = 0.01;  // kg/m
}
