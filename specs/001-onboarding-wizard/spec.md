# Feature Specification: First-Launch Onboarding Wizard

**Feature Branch**: `11724-onboarding-wizard`
**Created**: 2026-05-07
**Status**: Draft
**Input**: User description: "First-launch guided setup that walks the user through SmartSpin2k installation, BLE pairing, motor and shifter validation, optional WiFi/HRM setup, and ride-readiness — reusing existing settings screens where possible."

## Clarifications

### Session 2026-05-07

- Q: How should the wizard handle a BLE disconnect that occurs after a successful SmartSpin2k connection but before Completion? → A: Defer to the app's existing BLE-disconnect behavior; no wizard-specific handling.
- Q: Should the wizard explicitly check SmartSpin2k firmware version compatibility before Motor Test and Physical Shifter Test? → A: No wizard-specific firmware check; whatever firmware-version surfacing the app already performs on connect carries through the wizard.
- Q: What telemetry is required to support SC-002 (≥80% completion rate) and SC-005 (100% see fallback within 30s)? → A: Use whatever analytics the app already has, and only that; if none exists, treat SC-002 and SC-005 as QA-verified targets, not production-measured KPIs.
- Q: What should happen when a doc link ("It's Not Working", Hardware Installation) is tapped while the phone is offline? → A: Accept default OS-browser behavior; the wizard does not pre-check connectivity or provide custom offline UX.
- Q: What accessibility baseline must the wizard meet in v1? → A: Match the rest of the app's existing accessibility level; no wizard-specific accessibility uplift is required.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Guided First-Time Setup, Happy Path (Priority: P1)

A user who has just installed the SmartSpin2k app on a phone for the first time launches it. Instead of being dropped at a generic Bluetooth scan screen, they see a welcoming wizard that takes them step-by-step from "I just unboxed this" through to "I am ready to ride," reusing the app's existing connection, settings, shifter, and network screens behind a unified guided experience. On completion, the wizard does not appear again on subsequent launches.

**Why this priority**: This is the core value of the feature. It is the reason for the spec. Without this flow, no other priority matters. The current cold-start experience requires users to consult external documentation; this story replaces that with an in-app journey that materially reduces support burden and time-to-first-ride.

**Independent Test**: Install the app fresh (or clear app data) on a device with a powered, correctly-wired SmartSpin2k attached to a supported spin bike. Launch the app and follow the wizard end-to-end without referring to external documentation. Success = the user lands on a completion screen with both pairing instructions for a training app and an option to start a guided workout, and on the next app launch the wizard does NOT auto-start.

**Acceptance Scenarios**:

1. **Given** the app has never been launched before, **When** the user opens it, **Then** the wizard's Welcome step is shown instead of the scan screen.
2. **Given** the user is on the Welcome step, **When** they tap continue, **Then** they advance to a Bike Type Selection step offering Most Spin Bikes, Peloton Bike+, and Peloton Original.
3. **Given** the user has selected a bike type and progressed through hardware-installation guidance, **When** they tap "Scan" on the SmartSpin2k Connection step, **Then** the wizard performs the same BLE scan the existing scan screen performs and lists discovered SmartSpin2k devices.
4. **Given** the user selects a SmartSpin2k from the list, **When** the connection establishes, **Then** the wizard auto-advances to the next step without requiring the user to navigate to the main device screen.
5. **Given** the wizard has progressed to the Confirm Data Flowing step, **When** both power and cadence values are received from the configured data source for at least 3 continuous seconds, **Then** the wizard auto-advances to the Motor Test step.
6. **Given** the wizard is on the Motor Test step, **When** the user starts the test, **Then** the app commands two virtual upshifts and two virtual downshifts via the existing shifter command path and asks the user to confirm the knob physically rotated.
7. **Given** the user confirms the motor test succeeded, **When** the wizard advances to the Physical Shifter step, **Then** the app waits for an inbound resistance-change event and auto-confirms when one is received.
8. **Given** the user has completed all mandatory steps, **When** they finish the optional HRM and WiFi steps (or skip them), **Then** the wizard reaches the Completion step and persistently records that onboarding is complete.
9. **Given** the user has completed onboarding once, **When** they relaunch the app, **Then** they go directly to the existing scan screen without seeing the wizard.

---

### User Story 2 - Re-entry via "Guided Setup" Button (Priority: P2)

A user who completed onboarding (or skipped it earlier) wants to redo a portion of the setup — e.g., they bought a new bike, swapped a power meter, or are helping a friend set theirs up. They open the app, tap a clearly-labeled "Guided Setup" button on the existing scan screen, and re-enter the wizard.

**Why this priority**: Without this entry point, the wizard becomes a one-shot experience that users cannot intentionally revisit. This is a small addition on top of P1 but materially improves long-term utility and gives the user a discoverable "I want help" affordance.

**Independent Test**: With the `onboarding_completed` flag set to true, launch the app, tap "Guided Setup" on the scan screen, and verify the wizard appears starting at the Welcome step.

**Acceptance Scenarios**:

1. **Given** onboarding has previously completed, **When** the user is on the scan screen, **Then** a "Guided Setup" button is visible and tappable.
2. **Given** the user taps "Guided Setup," **When** the wizard launches, **Then** it begins at the Welcome step (not at a previously-saved checkpoint).
3. **Given** the user re-enters the wizard from the scan screen, **When** they exit before completion (back gesture, dismiss), **Then** the existing `onboarding_completed` flag remains `true` so the wizard does not auto-launch on the next cold start.

---

### User Story 3 - Auto-Advance with Failure Fallbacks (Priority: P2)

A user is following the wizard and reaches a step that is supposed to auto-detect something (BLE data flowing, physical shifter event). Detection fails — maybe their wiring is wrong, maybe their power meter is asleep. Instead of being stuck on a screen with no feedback, after 30 seconds they see a clear "we don't see anything yet" prompt with three actions: try again, link to troubleshooting documentation, or start the wizard over.

**Why this priority**: Auto-detection is great when it works, but real users will hit failure modes during initial setup more often than at any other time. A wizard that softlocks on a missing event would generate more support load than no wizard at all. This safety net is what makes the auto-advance UX trustworthy.

**Independent Test**: With a SmartSpin2k connected but with no data source configured (or pedals not turning), reach the "Confirm Data Flowing" step and wait. After 30 seconds, verify the fallback UI appears with the three actions, and verify each action behaves correctly.

**Acceptance Scenarios**:

1. **Given** the wizard is on an auto-detect step, **When** 30 seconds pass without the expected event, **Then** the user sees a non-blocking prompt offering "Try Again," "It's Not Working" (opens troubleshooting docs in external browser), and "Start Over" (restarts the wizard at the Welcome step).
2. **Given** the user is shown the failure prompt, **When** the expected event is detected after the prompt has appeared, **Then** the wizard still auto-advances and the prompt is dismissed.
3. **Given** the user taps "Start Over," **When** the wizard restarts, **Then** any previously connected device remains connected (the BLE session is not torn down) and any user-entered selections (bike type, etc.) are reset.

---

### User Story 4 - Resume Mid-Flow on Soft Interruption (Priority: P3)

A user starts the wizard, gets a phone call halfway through, and returns to the app. The wizard has not lost their place — they resume where they left off rather than starting at Welcome. This applies only within a single app session; if the app is fully killed, onboarding restarts from the Welcome step on the next launch (assuming `onboarding_completed` is still false).

**Why this priority**: This is a quality-of-life refinement. Users will tolerate restarting from Welcome once if their device is unreachable, but it will produce noticeable irritation if it happens because they switched apps for ten seconds. Lower priority than P1/P2 because it does not change feature scope, only resilience.

**Independent Test**: Launch the wizard, advance to step 5 or later, background the app, foreground it again, and confirm the same step is shown.

**Acceptance Scenarios**:

1. **Given** the wizard is at any step and the app is backgrounded, **When** the user foregrounds the app within the same process lifetime, **Then** the wizard is on the same step it was last showing.
2. **Given** the user has progressed mid-wizard and the OS terminates the app, **When** the app is relaunched cold, **Then** the wizard begins at the Welcome step with no resumption from a saved checkpoint.

---

### Edge Cases

- **Bluetooth adapter off at launch**: The wizard must yield to the existing Bluetooth-off screen until the adapter is on, then resume normally. It must not attempt to scan when the adapter is off.
- **No SmartSpin2k discoverable during scan**: The wizard's connection step must allow continued scanning indefinitely and must surface the same "Having Trouble?" guidance the existing scan screen surfaces, plus the standard 30-second auto-detect failure prompt for retry / troubleshooting / start-over.
- **User selects wrong bike type**: A back-step affordance must be available on every step from Bike Type Selection forward so the user can correct an earlier selection without restarting.
- **Motor test reports failure** ("the knob did not turn"): The wizard must present the same three options as auto-detect failure — Try Again, It's Not Working (link to troubleshooting docs), Start Over — and must not advance to subsequent steps.
- **Heart Rate Monitor not found / user has none**: The HRM step must always be skippable. Skip must not prevent reaching Completion.
- **WiFi credentials rejected by SmartSpin2k**: Surface the same failure UX the existing network settings screen uses, and treat WiFi as skippable. WiFi failure must not block Completion.
- **App killed and relaunched mid-wizard**: On next cold launch with `onboarding_completed = false`, the wizard begins at Welcome, not at the prior step.
- **User completes wizard, then clears app data**: Wizard auto-launches again on next start, as on first install. This is correct behavior (we have no other source of truth).
- **Peloton Bike+ user lands on the data-source step**: The single screen explains that Bike+ requires either Grupetto or a supported BLE power meter; selecting "power meter" leads to the same BLE scan the Most Spin Bikes path uses; selecting "Grupetto" presents brief written guidance and links to the docs site.
- **Demo mode**: The hidden demo-mode tap-target on the existing scan screen must remain accessible. Demo mode must bypass the onboarding wizard (the wizard is not meaningful without real hardware).

## Requirements *(mandatory)*

### Functional Requirements

#### Wizard Lifecycle and Persistence

- **FR-001**: The system MUST persist a single boolean `onboarding_completed` flag across app launches.
- **FR-002**: On cold launch, the system MUST display the wizard's Welcome step instead of the scan screen if `onboarding_completed` is false.
- **FR-003**: On cold launch, the system MUST display the existing scan screen (current behavior) if `onboarding_completed` is true.
- **FR-004**: The system MUST set `onboarding_completed` to true only when the user reaches the Completion step.
- **FR-005**: The system MUST NOT set `onboarding_completed` to true if the user exits the wizard early (back gesture, app dismissed, process terminated).
- **FR-006**: Within a single app process, the system MUST preserve the current wizard step across app backgrounding and foregrounding so the user resumes where they left off.
- **FR-007**: Across cold launches, the system MUST NOT resume to a mid-wizard step; if `onboarding_completed` is false at cold launch, the wizard MUST begin at Welcome.
- **FR-008**: The scan screen MUST display a "Guided Setup" button that launches the wizard at the Welcome step regardless of the value of `onboarding_completed`.
- **FR-009**: Re-entering the wizard via the "Guided Setup" button MUST NOT change the value of `onboarding_completed`.

#### Step Sequence

- **FR-010**: The wizard MUST present the following step order, branching on bike type as specified:
  1. Welcome
  2. Bike Type Selection (Most Spin Bikes / Peloton Bike+ / Peloton Original)
  3. Hardware Installation (common to all bike types; opens documentation in external browser)
  4. Wiring (path-specific copy: Most Spin = power + shifter; Bike+ = power + shifter, no Peloton connectors; Peloton Original = power + shifter + sensor cable)
  5. Side Switch (Peloton Original only — Tablet Mode = UP, Headless Mode = DOWN)
  6. SmartSpin2k Connection (BLE scan and select)
  7. Data Source (path-specific):
     - Most Spin Bikes: BLE scan + select bike or power meter
     - Peloton Bike+: single screen explaining Grupetto vs power meter; if power meter, BLE scan + pair
     - Peloton Original: wired — no pairing needed; in Tablet Mode, instruct user to start a ride first
  8. Confirm Data Flowing (auto-advance when power AND cadence detected ≥ 3s)
  9. Motor Test (app sends +2 then -2 shifts; user confirms)
  10. Physical Shifter Test (auto-detect inbound resistance change event)
  11. Heart Rate Monitor (optional, skippable)
  12. WiFi / Dircon Setup (optional, skippable)
  13. Completion (records `onboarding_completed = true`; offers two outbound paths)
- **FR-011**: The Completion step MUST present two outbound options: (a) "How to connect your training app" — a screen instructing the user to select their SmartSpin2k as the power meter, smart trainer, cadence sensor, and (optional) heart rate monitor in their training app of choice; and (b) "Start a Guided Workout" — entering the existing in-app workout flow.
- **FR-012**: Every step from Bike Type Selection onward MUST provide a back-step affordance to the previous step.

#### Reuse of Existing Functionality

- **FR-013**: The SmartSpin2k Connection step MUST use the same BLE scan, filter, and connection flow as the existing scan screen.
- **FR-014**: The Data Source step (when BLE scan is required) MUST surface the same data-source / power-meter selection UI used elsewhere in the app's settings.
- **FR-015**: The Motor Test step MUST issue virtual shift commands via the same control path used by the existing shifter screen.
- **FR-016**: The Physical Shifter Test step MUST observe the same inbound shifter / resistance-change events the existing shifter screen observes.
- **FR-017**: The Heart Rate Monitor step MUST configure the SmartSpin2k as a heart-rate-monitor relay using the existing in-app HRM selection mechanism (so paired HRMs are bridged to training apps via the SmartSpin2k, benefiting users on platforms like Apple TV with limited concurrent BLE connections).
- **FR-018**: The WiFi step MUST collect a 2.4 GHz SSID and password using the existing network-settings WiFi configuration path; the wizard MUST explain WiFi enables automatic firmware updates and DirCon support.
- **FR-019**: The wizard MUST NOT introduce a parallel implementation of any setting screen; instead it MUST embed or invoke the existing screens, restricted to the relevant fields.
- **FR-019a**: If the BLE link to a connected SmartSpin2k drops at any wizard step after the SmartSpin2k Connection step, the wizard MUST defer to the app's existing BLE-disconnect behavior (the same recovery, banners, retries, and reconnection logic used elsewhere in the app). The wizard MUST NOT implement a parallel disconnect-recovery flow.
- **FR-019b**: The wizard MUST NOT introduce a wizard-specific firmware-version check or firmware-compatibility gate. Any firmware-version surfacing the app already performs on connect (warnings, version display, update prompts) carries through the wizard without modification. Failures attributable to incompatible firmware fall through to the standard 30-second auto-detect fallback (FR-022) at the affected step.
- **FR-019c**: The wizard's accessibility level (screen reader support, dynamic type, contrast, focus order, RTL) MUST match the existing app's baseline. The wizard MUST NOT introduce a wizard-specific accessibility uplift, and conversely MUST NOT regress below the existing baseline.

#### Auto-Advance Behavior

- **FR-020**: At the Confirm Data Flowing step, the system MUST auto-advance to the next step when both power AND cadence values are detected continuously for ≥ 3 seconds.
- **FR-021**: At the Physical Shifter Test step, the system MUST auto-advance to the next step when an inbound resistance-change event is observed.
- **FR-022**: At any auto-advance step, if the expected event has not occurred within 30 seconds of step entry, the system MUST display a non-blocking fallback prompt offering: "Try Again" (resets the 30-second timer), "It's Not Working" (opens https://docs.smartspin2k.com/documentation/troubleshooting in an external browser), and "Start Over" (returns the user to the Welcome step).
- **FR-023**: After the fallback prompt has appeared, the system MUST still auto-advance if the expected event subsequently occurs, and MUST dismiss the prompt at that time.

#### Failure Handling

- **FR-024**: At the Motor Test step, if the user reports the knob did NOT turn, the system MUST present the same three options as FR-022: Try Again, It's Not Working (troubleshooting docs link), Start Over.
- **FR-025**: At the SmartSpin2k Connection step, the system MUST surface the same "Having Trouble?" guidance the existing scan screen surfaces when no devices appear.
- **FR-026**: "It's Not Working" links MUST point to https://docs.smartspin2k.com/documentation/troubleshooting and MUST open in an external browser.
- **FR-027**: The Hardware Installation step's documentation link MUST point to https://docs.smartspin2k.com/getting-started/installation.html and MUST open in an external browser.
- **FR-027a**: The wizard MUST NOT pre-check phone connectivity before opening any external doc link. If the phone is offline, the OS browser's default "no internet" handling is the expected behavior; the wizard does not provide a custom offline message or bundled offline content.
- **FR-028**: The "Start Over" action MUST return the user to the Welcome step, reset all wizard-internal selections (bike type, etc.), and MUST NOT tear down any active BLE connection.

#### Optional Steps

- **FR-029**: The Heart Rate Monitor step MUST be skippable via an explicit "Skip" affordance; skipping MUST allow the user to reach Completion.
- **FR-030**: The WiFi step MUST be skippable via an explicit "Skip" affordance; skipping MUST allow the user to reach Completion.
- **FR-031**: The system MUST visually distinguish optional steps from mandatory steps so the user understands which are skippable.

#### Bluetooth Adapter and Demo Mode

- **FR-032**: When the Bluetooth adapter is off, the system MUST defer wizard steps that require BLE and MUST display the existing Bluetooth-off screen until the adapter is on.
- **FR-033**: Demo mode (entered via the existing hidden tap-target on the scan screen) MUST bypass the wizard.

### Key Entities

- **OnboardingState**: A small piece of persistent app state with the single attribute `onboarding_completed: boolean`. Stored locally on the device. Read on cold launch to decide whether to show the wizard or the scan screen.
- **WizardSession**: In-memory state representing the user's current pass through the wizard. Includes the current step, selected bike type, and any other transient selections. Survives backgrounding within a single process; does not survive process termination.
- **OnboardingStep**: A discrete screen in the wizard. Has a type (informational, action, auto-detect, optional), a "next" transition (sometimes branching on prior selections), a "back" transition, and (where applicable) an auto-advance condition and a 30-second fallback timer.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user with correctly-installed hardware can go from first app launch to Completion in under 10 minutes without consulting external documentation.
- **SC-002**: At least 80% of first-time users who reach the Welcome step also reach the Completion step within their first session (measured against the population that does not abandon for hardware reasons). Measured via whatever analytics the app already provides; if no analytics exist, this is a QA-verified target rather than a production-measured KPI, and v1 does NOT introduce a new telemetry stack to instrument it.
- **SC-003**: The wizard does not auto-launch on any subsequent app start once a user has completed it; verified by 100% of post-completion launches landing on the scan screen.
- **SC-004**: Zero steps in the wizard duplicate logic that already exists in the scan, settings, shifter, network, or workout screens — every step either embeds or invokes the existing implementation.
- **SC-005**: When auto-detection fails on an auto-detect step, 100% of users see the fallback prompt within 30 seconds. Verified during QA via deterministic timer testing; v1 does NOT introduce production telemetry to measure this.
- **SC-006**: Support requests citing "I don't know how to install / set up my SmartSpin2k for the first time" decrease meaningfully after release (qualitative target, tracked via support channels).
- **SC-007**: Users completing the WiFi step have functional automatic firmware updates and DirCon connectivity without further action; verified end-to-end on a representative device.

## Assumptions

- The wizard is a Flutter feature shipped inside the existing SmartSpin2k config app; no separate distribution channel.
- `SharedPreferences` (or the equivalent already in use by the app) is the persistence mechanism for the `onboarding_completed` flag. The flag is per-app-install; uninstalling and reinstalling the app re-triggers the wizard, which matches user expectations.
- The Peloton Bike+ branch in v1 is a single screen explaining Grupetto vs supported power meter, with the power-meter sub-flow reusing the generic BLE scan path. Sideloading instructions for Grupetto are not implemented in-app; the user is directed to docs.smartspin2k.com.
- Installation help and troubleshooting documentation are hosted at docs.smartspin2k.com and are accessed via the OS's external browser. No markdown rendering or in-app webview is implemented in v1.
- WiFi setup uses the existing 2.4 GHz SSID/password flow already implemented in the app's network settings screen. No AP-mode/captive-portal flow is introduced.
- The Heart Rate Monitor step pairs the HRM through the SmartSpin2k as a relay using the existing settings-screen mechanism; this is not a workout-app-only pairing.
- The 30-second auto-detect timeout applies only to "Confirm Data Flowing" and "Physical Shifter Test." Other auto-detect-like steps (BLE scan results) use their existing timing.
- "Start Over" resets in-memory wizard selections only; it does not clear the `onboarding_completed` flag (which is false during the wizard anyway) and does not disconnect any active BLE device.
- The existing Bluetooth-off screen continues to gate any BLE-dependent wizard step.
- "Future ideas" listed in the ideation document — homing setup with subsequent ride instructions, intervals.icu config wizard, and unhappy-path documentation beyond the troubleshooting link — are explicitly out of scope for v1.
