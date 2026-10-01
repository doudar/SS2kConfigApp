import 'bleConstants.dart';

/// Firmware uses extreme values for unknown/unhomed travel. Never turn those
/// sentinels into a seemingly valid gauge or limit diagnosis.
bool hasStepperTravelRange(double? minimum, double? maximum) =>
    minimum != null &&
    maximum != null &&
    minimum.isFinite &&
    maximum.isFinite &&
    minimum > -100000000 &&
    maximum < 100000000 &&
    maximum > minimum;

double? stepperTravelProgress(
  double? position,
  double? minimum,
  double? maximum,
) {
  if (position == null ||
      !position.isFinite ||
      !hasStepperTravelRange(minimum, maximum))
    return null;
  return ((position - minimum!) / (maximum! - minimum)).clamp(0.0, 1.0);
}

/// Explains observed conditions without pretending the wire protocol supplies
/// a rejection reason. Used only after an unconfirmed or rejected shift.
String shiftFeedback({
  required bool connected,
  required bool homing,
  required bool noCadence,
  required int mode,
  required int delta,
  double? position,
  double? minimum,
  double? maximum,
  double? stepSize,
  double? targetWatts,
  double? maxWatts,
}) {
  if (!connected)
    return 'SmartSpin2k disconnected before the shift was confirmed.';
  if (homing) return 'Homing is active. Wait for it to finish before shifting.';
  if (mode == FTMSOpCodes.SET_TARGET_POWER) {
    if (targetWatts != null &&
        ((delta > 0 &&
                maxWatts != null &&
                maxWatts > 0 &&
                targetWatts + delta * 10 > maxWatts) ||
            (delta < 0 && targetWatts + delta * 10 < 0))) {
      return 'The requested shift exceeds the target power limit.';
    }
  } else if (mode != FTMSOpCodes.SET_TARGET_RESISTANCE_LEVEL &&
      hasStepperTravelRange(minimum, maximum) &&
      position != null &&
      position.isFinite &&
      stepSize != null &&
      stepSize.isFinite &&
      stepSize > 0) {
    final proposed = position + delta * stepSize;
    if (delta > 0 && proposed > maximum!) {
      return 'The requested shift exceeds the upper travel limit.';
    }
    if (delta < 0 && proposed < minimum!) {
      return 'The requested shift exceeds the lower travel limit.';
    }
  }
  if (noCadence)
    return 'No cadence detected yet. Start pedaling and try again.';
  return 'SmartSpin2k did not confirm the requested shift. It may be blocked by a limit or homing. Try again once you are pedaling.';
}
