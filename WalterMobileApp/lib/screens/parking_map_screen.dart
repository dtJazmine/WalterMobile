import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'parking_slot.dart';
import 'parking_stall_tile.dart';
import 'qr_generation_screen.dart';
import '../firebase_db.dart';

/// Standalone screen wrapper. Use this only if you need to push the
/// parking map as its own route with its own AppBar.
/// For embedding inside home_screen.dart's existing Scaffold, use
/// [ParkingMapBody] directly instead.
///
/// NOTE: when embedding [ParkingMapBody] inside another Scaffold
/// (e.g. home_screen.dart), also add a [FloatingQrButton] to that
/// Scaffold's `bottomNavigationBar` — see the bottom of this file
/// for a ready-to-use helper. ParkingMapBody itself has no Scaffold,
/// so it can't pin its own bottom bar; only the parent Scaffold can.
class ParkingMapScreen extends StatelessWidget {
  const ParkingMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        elevation: 0,
        title: const Text(
          'Parking map',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
      ),
      body: const SafeArea(child: ParkingMapBody()),
      // Standalone route owns its own Scaffold, so it CAN pin the button.
      bottomNavigationBar: SafeArea(
        minimum: EdgeInsets.zero,
        child: FloatingQrButton(
          label: 'Generate QR code',
          onPressed: () {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Please sign in again.')),
              );
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => QrGenerationScreen(accountId: uid),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The live parking map content only — no Scaffold, no AppBar, and
/// no Generate QR button. Designed to be dropped into another screen's
/// body, e.g. home_screen.dart. The parent screen is responsible for
/// adding its own FloatingQrButton to its Scaffold's bottomNavigationBar.
class ParkingMapBody extends StatefulWidget {
  const ParkingMapBody({super.key});

  @override
  State<ParkingMapBody> createState() => _ParkingMapBodyState();
}

class _ParkingMapBodyState extends State<ParkingMapBody> {
  final String _selectedSection = 'front';

  // Scroll controller for the page's SingleChildScrollView.
  final ScrollController _scrollController = ScrollController();

  // Bumps whenever live-relevant state changes (occupancy, confirmed
  // slot, pwd visibility) so any pushed _SectionLiveMapScreen can stay
  // in sync with this screen's state without its own Firebase
  // subscription. _SectionLiveMapScreen listens to this via
  // AnimatedBuilder and just re-reads the getter closures below.
  final ChangeNotifier _liveUpdates = ChangeNotifier();

  // Set once the user confirms they're parked in a specific slot.
  // Drives the top banner switching from "SUGGESTED FOR YOU" to
  // "CURRENT PARKING SLOT".
  String? _confirmedSlotLabel;

  // The raw slot id (e.g. "F3") of the confirmed slot. Used to force
  // that specific tile to render as occupied + highlighted in the grid,
  // regardless of what the live/static isOccupied status says.
  String? _confirmedSlotId;

  // The section key ("front"/"side"/"back") that _confirmedSlotId belongs
  // to. Needed because the driver might switch to a different section's
  // view before tapping a new slot, so we can't just assume "current
  // section" when we need to free up the old slot.
  String? _confirmedSectionKey;

  // True right after the user confirms they've left their slot. Drives
  // the banner to show a "THANK YOU" message briefly before it settles
  // back to "SUGGESTED FOR YOU".
  bool _showThankYouBanner = false;

  // Auto-reverts the thank-you banner back to the default suggestion.
  Timer? _thankYouTimer;

  // True while we're checking Firebase for a slot the current account
  // already has reserved (e.g. right after login/app restart).
  bool _restoringSlot = true;

  // Whether the signed-in account is itself registered as PWD (read
  // from users/{uid}.isPwd in Firestore, set at registration — see
  // register_screen.dart). Accounts registered as PWD always see
  // PWD-reserved slots; everyone else has them hidden by default.
  bool _isAccountPwd = false;
  bool _loadingPwdStatus = true;

  // Session-only override for non-PWD accounts: "I am with a PWD" —
  // lets a driver who isn't PWD-registered themselves reveal PWD slots
  // for this visit. Deliberately NOT persisted to the account or
  // Firebase; it resets every time this screen is rebuilt/reopened, so
  // it can't be used to permanently unlock PWD slots with one tap.
  bool _withPwd = false;

  // Single source of truth for whether PWD-reserved slots should be
  // visible anywhere on this screen (grid, compass overview, stats).
  bool get _pwdSlotsVisible => _isAccountPwd || _withPwd;

  // Live occupancy for every slot in every section, keyed by slot id
  // (e.g. "F1", "S12", "BT1", "BM1", "BC1"). Populated from a realtime
  // listener on /slots in Firebase and kept up to date for as long as
  // this screen is mounted. This is what makes the mobile map match the
  // web dashboard — previously the grid only ever showed its static
  // demo data (isOccupied: false for everything) except for the
  // driver's own confirmed slot.
  Map<String, bool> _liveOccupancy = {};

  StreamSubscription<DatabaseEvent>? _slotsSubscription;

  @override
  void initState() {
    super.initState();
    _restoreConfirmedSlot();
    _listenToSlots();
    _loadAccountPwdStatus();
  }

  @override
  void dispose() {
    _liveUpdates.dispose();
    _thankYouTimer?.cancel();
    _scrollController.dispose();
    _slotsSubscription?.cancel();
    super.dispose();
  }

  /// Reads users/{uid}.isPwd from Firestore so this screen knows whether
  /// the signed-in account is itself registered as PWD. Defaults to
  /// false (PWD slots hidden) if the user is signed out, the read fails,
  /// or the field is missing — fail closed rather than leaking
  /// PWD-reserved slots to an account that isn't registered for them.
  Future<void> _loadAccountPwdStatus() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loadingPwdStatus = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final isPwd = (doc.data()?['isPwd'] as bool?) ?? false;
      if (mounted) {
        setState(() {
          _isAccountPwd = isPwd;
          _loadingPwdStatus = false;
        });
        _liveUpdates.notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load PWD status: $e');
      if (mounted) setState(() => _loadingPwdStatus = false);
    }
  }

  /// Subscribes to /slots in Firebase Realtime Database and keeps
  /// [_liveOccupancy] up to date. Expects the shape written by
  /// [_writeSlotTransition] / [_writeSlotFree]: /slots/{sectionKey}/{slotId}/sensor
  /// is either "occupied" or "vacant". Any slot not present in the
  /// snapshot keeps falling back to its static isOccupied flag via
  /// [_effectiveOccupied].
  void _listenToSlots() {
    _slotsSubscription = rtdb.ref('slots').onValue.listen((event) {
      final raw = event.snapshot.value;

      print("========== FIREBASE ==========");
      print(raw);

      if (!mounted) return;

      if (raw == null) {
        setState(() => _liveOccupancy = {});
        _liveUpdates.notifyListeners();
        return;
      }

      final occupancy = <String, bool>{};
      final sectionsMap = Map<dynamic, dynamic>.from(raw as Map);

      for (final sectionEntry in sectionsMap.entries) {
        final slotsRaw = sectionEntry.value;
        if (slotsRaw is! Map) continue;

        final slotsMap = Map<dynamic, dynamic>.from(slotsRaw);

        for (final slotEntry in slotsMap.entries) {
          final slotId = slotEntry.key.toString();
          final slotData = Map<dynamic, dynamic>.from(slotEntry.value);

          occupancy[slotId] = slotData['sensor'] == 'occupied';

          print("$slotId -> ${occupancy[slotId]}");
        }
      }

      print("LIVE OCCUPANCY");
      print(occupancy);

      setState(() {
        _liveOccupancy = occupancy;
      });
      _liveUpdates.notifyListeners();
    });
  }

  /// Returns whether [slot] should currently render as occupied, live
  /// Firebase data taking priority over the static demo flag baked into
  /// [_sections]. This is the single source of truth used everywhere in
  /// the UI (grid tiles, compass overview, stats) so nothing can drift
  /// out of sync with what the database actually says.
  bool _effectiveOccupied(ParkingSlot slot) {
    return _liveOccupancy[slot.id] ?? slot.isOccupied;
  }

  /// Reads /user_slots/{uid} from Firebase and, if the account already
  /// has a slot reserved, restores _confirmedSlotId/_confirmedSlotLabel/
  /// _confirmedSectionKey from that — instead of trusting local widget
  /// state, which resets to null on every relogin/app restart. This is
  /// what keeps the app in sync with whatever the database (and the web
  /// dashboard) actually says is occupied.
  Future<void> _restoreConfirmedSlot() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _restoringSlot = false);
      return;
    }

    try {
      final snap =
          await rtdb.ref('user_slots/$uid').get();

      if (!mounted) return;

      if (!snap.exists || snap.value == null) {
        setState(() => _restoringSlot = false);
        return;
      }

      final data = Map<dynamic, dynamic>.from(snap.value as Map);
      final sectionKey = data['sectionKey'] as String?;
      final slotId = data['slotId'] as String?;

      if (sectionKey == null || slotId == null) {
        setState(() => _restoringSlot = false);
        return;
      }

      final section = _sections[sectionKey];
      if (section == null) {
        setState(() => _restoringSlot = false);
        return;
      }

      setState(() {
        _confirmedSlotId = slotId;
        _confirmedSectionKey = sectionKey;
        _confirmedSlotLabel = '${section.label} Parking — $slotId';
        _restoringSlot = false;
      });
      _liveUpdates.notifyListeners();
    } catch (e) {
      debugPrint('Failed to restore reserved slot: $e');
      if (mounted) setState(() => _restoringSlot = false);
    }
  }

  // Layout-only data now — ids, pwd flags, and section/sub-area
  // structure. Occupied/vacant status no longer comes from here at
  // render time; see _effectiveOccupied(), which prefers live Firebase
  // data and only falls back to isOccupied below if Firebase hasn't
  // reported a status for that slot yet.
  final Map<String, ParkingSection> _sections = {
    'front': ParkingSection(
      key: 'front',
      label: 'Front',
      subAreas: [
        ParkingSubArea(
          key: 'front_left',
          label: 'Front — Left side parking',
          leftColumn: const [
            ParkingSlot(id: 'F16', isOccupied: false),
            ParkingSlot(id: 'F17', isOccupied: false),
            ParkingSlot(id: 'F18', isOccupied: false),
            ParkingSlot(id: 'F19', isOccupied: false),
            ParkingSlot(id: 'F20', isOccupied: false),
            ParkingSlot(id: 'F21', isOccupied: false),
            ParkingSlot(id: 'F22', isOccupied: false),
          ],
          rightColumn: const [
            ParkingSlot(id: 'F1', isOccupied: false),
            ParkingSlot(id: 'F2', isOccupied: false),
            ParkingSlot(id: 'F3', isOccupied: false),
            ParkingSlot(id: 'F4', isOccupied: false),
            ParkingSlot(id: 'F5', isOccupied: false),
            ParkingSlot(id: 'F6', isOccupied: false),
            ParkingSlot(id: 'F7', isOccupied: false),
            ParkingSlot(id: 'F8', isOccupied: false),
            ParkingSlot(id: 'F9', isOccupied: false, isPwd: true),
          ],
        ),
        ParkingSubArea(
          key: 'front_right',
          label: 'Front — Right side parking',
          leftColumn: const [
            ParkingSlot(id: 'F23', isOccupied: false),
            ParkingSlot(id: 'F24', isOccupied: false),
            ParkingSlot(id: 'F25', isOccupied: false),
            ParkingSlot(id: 'F26', isOccupied: false),
            ParkingSlot(id: 'F27', isOccupied: false),
            ParkingSlot(id: 'F28', isOccupied: false),
            ParkingSlot(id: 'F29', isOccupied: false),
            ParkingSlot(id: 'F30', isOccupied: false),
          ],
          rightColumn: const [
            ParkingSlot(id: 'F10', isOccupied: false, isPwd: true),
            ParkingSlot(id: 'F11', isOccupied: false, isPwd: true),
            ParkingSlot(id: 'F12', isOccupied: false),
            ParkingSlot(id: 'F13', isOccupied: false),
            ParkingSlot(id: 'F14', isOccupied: false),
            ParkingSlot(id: 'F15', isOccupied: false),
          ],
        ),
      ],
    ),
    'side': ParkingSection(
      key: 'side',
      label: 'Side',
      subAreas: [
        ParkingSubArea(
          key: 'side_main',
          label: 'Side parking',
          // Straight single-line layout — no drive lane split.
          // All 60 slots in one column, S1 to S60, aligned right.
          leftColumn: const [],
          rightColumn: List.generate(
            60,
            (i) => ParkingSlot(id: 'S${i + 1}', isOccupied: false),
          ),
        ),
      ],
    ),
    'back': ParkingSection(
      key: 'back',
      label: 'Back',
      // Split by vehicle type instead of one undivided lot — same
      // left/right-per-sub-area shape as Front, just partitioned by
      // vehicle type (tricycle/motorcycle/car) instead of physical
      // side. Each sub-area still gets its own drive-lane split down
      // the middle. Counts: tricycle 22, motorcycle 42, car 58 — 122
      // total, unchanged from the old undivided back lot.
      subAreas: [
        ParkingSubArea(
          key: 'back_car',
          label: 'Back — Car parking',
          // BC1–BC29 left, BC30–BC58 right. BC6–BC9 carry over the
          // reserved-PWD slots that used to be B6–B9 in the old
          // undivided layout.
          leftColumn: List.generate(
            29,
            (i) {
              final id = 'BC${i + 1}';
              final isPwd = const ['BC6', 'BC7', 'BC8', 'BC9'].contains(id);
              return ParkingSlot(id: id, isOccupied: false, isPwd: isPwd);
            },
          ),
          rightColumn: List.generate(
            29,
            (i) => ParkingSlot(id: 'BC${i + 30}', isOccupied: false),
          ),
        ),
        ParkingSubArea(
          key: 'back_motorcycle',
          label: 'Back — Motorcycle parking',
          // BM1–BM21 left, BM22–BM42 right.
          leftColumn: List.generate(
            21,
            (i) => ParkingSlot(id: 'BM${i + 1}', isOccupied: false),
          ),
          rightColumn: List.generate(
            21,
            (i) => ParkingSlot(id: 'BM${i + 22}', isOccupied: false),
          ),
        ),
        ParkingSubArea(
          key: 'back_tricycle',
          label: 'Back — Tricycle parking',
          // BT1–BT11 left, BT12–BT22 right.
          leftColumn: List.generate(
            11,
            (i) => ParkingSlot(id: 'BT${i + 1}', isOccupied: false),
          ),
          rightColumn: List.generate(
            11,
            (i) => ParkingSlot(id: 'BT${i + 12}', isOccupied: false),
          ),
        ),
      ],
    ),
  };

  /// Pushes a dedicated full-screen live map for [key]'s section —
  /// used by the compass overview zone boxes.
  /// The pushed screen re-reads this state's live data (occupancy,
  /// confirmed slot, pwd visibility) via getter closures and rebuilds
  /// whenever [_liveUpdates] fires, so it stays in sync without its
  /// own Firebase subscription.
  void _openSectionLiveMap(String key) {
    final section = _sections[key];
    if (section == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _SectionLiveMapScreen(
          section: section,
          listenable: _liveUpdates,
          getConfirmedSlotId: () => _confirmedSlotId,
          getConfirmedSlotLabel: () => _confirmedSlotLabel,
          getShowThankYou: () => _showThankYouBanner,
          getLiveOccupancy: () => _liveOccupancy,
          getPwdSlotsVisible: () => _pwdSlotsVisible,
          getShowPwdToggle: () => !_loadingPwdStatus && !_isAccountPwd,
          getWithPwd: () => _withPwd,
          onWithPwdChanged: (value) {
            setState(() => _withPwd = value);
            _liveUpdates.notifyListeners();
          },
          onSlotTap: (slot) => _handleSlotTap(slot, section.label, section.key),
          onConfirmedSlotTap: (slot) =>
              _handleLeaveSlotTap(slot, section.label, section.key),
        ),
      ),
    );
  }

  /// Frees a single slot in Firebase — used only for the "leave with no
  /// new slot involved" case (_handleLeaveSlotTap). Awaited and returns
  /// whether the write actually succeeded so callers can roll the UI
  /// back on failure instead of silently drifting out of sync.
  Future<bool> _writeSlotFree({
    required String sectionKey,
    required String slotId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in again.')),
        );
      }
      return false;
    }

    final updates = <String, dynamic>{
      'slots/$sectionKey/$slotId/sensor': 'vacant',
      'slots/$sectionKey/$slotId/reservedBy': null,
      'user_slots/$uid': null,
    };

    try {
      await rtdb.ref().update(updates);
      return true;
    } catch (e) {
      debugPrint('Failed to free slot $sectionKey/$slotId: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Couldn't sync with the server ($e). Check your connection and try again.",
            ),
          ),
        );
      }
      return false;
    }
  }

  /// Atomically frees [oldSlotId] (if any) and claims [newSlotId] for the
  /// signed-in account in a SINGLE Firebase multi-path update.
  ///
  /// This is the fix for slots getting "stuck" occupied when switching:
  /// the old version fired two independent, un-awaited writes — one to
  /// vacate the old slot, one to claim the new one — with nothing
  /// checking whether either actually succeeded. If the vacate write
  /// failed or lagged for any reason (dropped connection, reordering),
  /// the app moved on locally to show the new slot as confirmed while
  /// the old slot silently stayed "occupied" in Firebase forever — which
  /// is exactly what shows up as "stuck" on the web dashboard, since it
  /// reads the same data. Bundling both halves into one update() call
  /// means they either both land or neither does, and we now await the
  /// result and roll the UI back if it fails instead of assuming success.
  Future<bool> _writeSlotTransition({
    required String newSectionKey,
    required String newSlotId,
    String? oldSectionKey,
    String? oldSlotId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in again.')),
        );
      }
      return false;
    }

    final updates = <String, dynamic>{
      'slots/$newSectionKey/$newSlotId/sensor': 'occupied',
      'slots/$newSectionKey/$newSlotId/reservedBy': uid,
      'user_slots/$uid': {'sectionKey': newSectionKey, 'slotId': newSlotId},
    };

    if (oldSectionKey != null && oldSlotId != null) {
      updates['slots/$oldSectionKey/$oldSlotId/sensor'] = 'vacant';
      updates['slots/$oldSectionKey/$oldSlotId/reservedBy'] = null;
    }

    // TEMP DEBUG — trace exactly what gets sent to Firebase and whether
    // the write actually succeeds. Remove once the F1-stuck-occupied
    // issue is confirmed fixed.
    print('========== TRANSITION UPDATES ==========');
    print('oldSectionKey: $oldSectionKey, oldSlotId: $oldSlotId');
    print('newSectionKey: $newSectionKey, newSlotId: $newSlotId');
    print(updates);

    try {
      await rtdb.ref().update(updates);
      print('========== TRANSITION WRITE SUCCEEDED ==========');
      return true;
    } catch (e) {
      print('========== TRANSITION WRITE FAILED: $e ==========');
      debugPrint(
          'Failed to write slot transition ($oldSectionKey/$oldSlotId -> $newSectionKey/$newSlotId): $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Couldn't sync with the server ($e). Check your connection and try again.",
            ),
          ),
        );
      }
      return false;
    }
  }

  void _handleSlotTap(ParkingSlot slot, String sectionLabel, String sectionKey) {
    // Occupied slots aren't tappable in the grid (see _ParkingGrid),
    // but guard here too in case this is ever called some other way.
    // Uses live occupancy, not the static flag, so a slot someone else
    // just took can't be tapped in the brief window before the grid
    // rebuilds.
    if (_effectiveOccupied(slot)) return;

    // Already parked somewhere else? Make them confirm leaving that slot
    // before we let them confirm a new one — prevents "double parking"
    // in the data.
    if (_confirmedSlotId != null && _confirmedSlotId != slot.id) {
      _promptLeaveBeforeSwitching(
        newSlot: slot,
        newSectionLabel: sectionLabel,
        newSectionKey: sectionKey,
      );
      return;
    }

    _showConfirmSlotDialog(slot, sectionLabel, sectionKey);
  }

  // Shown when the driver already has a confirmed slot and taps a
  // *different* available slot. Asks them to confirm leaving the old
  // slot first; only on confirmation do we free the old slot and chain
  // straight into the normal "confirm this new slot" dialog.
  void _promptLeaveBeforeSwitching({
    required ParkingSlot newSlot,
    required String newSectionLabel,
    required String newSectionKey,
  }) {
    final oldSlotLabel = _confirmedSlotLabel ?? 'your current slot';
    final oldSlotId = _confirmedSlotId!;
    final oldSectionKey = _confirmedSectionKey!;

    // TEMP DEBUG — confirm what we captured BEFORE local state gets
    // cleared below, since that's the data _writeSlotTransition will
    // eventually receive as oldSectionKey/oldSlotId.
    print('========== PROMPT LEAVE BEFORE SWITCHING ==========');
    print('oldSlotId: $oldSlotId, oldSectionKey: $oldSectionKey');

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _ParkingDialog(
        headerTitle: 'LEAVING PARKING SLOT',
        subtitleText: oldSlotLabel,
        question:
            "You're currently parked in $oldSlotLabel. Leave this slot to park in $newSectionLabel Parking — ${newSlot.id}?",
        confirmLabel: "YES, I'M LEAVING",
        confirmColor: AppColors.slotOccupied,
        onClose: () => Navigator.of(dialogContext).pop(),
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          setState(() {
            _confirmedSlotLabel = null;
            _confirmedSlotId = null;
            _confirmedSectionKey = null;
          });
          _liveUpdates.notifyListeners();

          // Don't write to Firebase yet. Walk straight into confirming
          // the new slot, carrying the old slot's info along — the
          // actual free-old + claim-new write happens as a single
          // atomic update once the new slot is confirmed too. See
          // _writeSlotTransition for why this matters.
          _showConfirmSlotDialog(
            newSlot,
            newSectionLabel,
            newSectionKey,
            previousSlotId: oldSlotId,
            previousSectionKey: oldSectionKey,
            previousSlotLabel: oldSlotLabel,
          );
        },
      ),
    );
  }

  void _showConfirmSlotDialog(
    ParkingSlot slot,
    String sectionLabel,
    String sectionKey, {
    String? previousSlotId,
    String? previousSectionKey,
    String? previousSlotLabel,
  }) {
    // TEMP DEBUG — confirm exactly what this dialog will pass into
    // _writeSlotTransition as the "old" slot when it's confirmed.
    print('========== SHOW CONFIRM SLOT DIALOG ==========');
    print('newSlotId: ${slot.id}, newSectionKey: $sectionKey');
    print('previousSlotId: $previousSlotId, previousSectionKey: $previousSectionKey');

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _ParkingDialog(
        headerTitle: 'PARKING SLOT CONFIRMATION',
        subtitleText: '$sectionLabel Parking — ${slot.id}',
        question: 'Are you currently parked in this slot?',
        confirmLabel: 'YES, I AM',
        confirmColor: AppColors.slotAvailable,
        onClose: () => Navigator.of(dialogContext).pop(),
        onConfirm: () async {
          // Cancel any pending thank-you auto-revert so it doesn't
          // stomp on the newly confirmed slot a few seconds from now.
          _thankYouTimer?.cancel();
          final newLabel = '$sectionLabel Parking — ${slot.id}';
          setState(() {
            _confirmedSlotLabel = newLabel;
            _confirmedSlotId = slot.id;
            _confirmedSectionKey = sectionKey;
            _showThankYouBanner = false;
          });
          _liveUpdates.notifyListeners();
          Navigator.of(dialogContext).pop();

          // One atomic write: claim the new slot, and — if this
          // confirmation came from a switch — free the old one in the
          // same call. See _writeSlotTransition for why these can't be
          // two separate writes without risking a slot getting stuck.
          final success = await _writeSlotTransition(
            newSectionKey: sectionKey,
            newSlotId: slot.id,
            oldSectionKey: previousSectionKey,
            oldSlotId: previousSlotId,
          );

          if (!success && mounted) {
            // The write didn't actually land — don't leave the UI
            // claiming a slot Firebase never recorded. Roll back to
            // whatever was true before this confirmation.
            setState(() {
              _confirmedSlotId = previousSlotId;
              _confirmedSectionKey = previousSectionKey;
              _confirmedSlotLabel = previousSlotLabel;
            });
            _liveUpdates.notifyListeners();
          }
        },
      ),
    );
  }

  // Tapping the user's own (highlighted, red) slot asks whether they're
  // leaving. Confirming frees the slot back to available/green and
  // switches the banner to a "thank you" message for a few seconds.
  void _handleLeaveSlotTap(ParkingSlot slot, String sectionLabel, String sectionKey) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _ParkingDialog(
        headerTitle: 'LEAVING PARKING SLOT',
        subtitleText: '$sectionLabel Parking — ${slot.id}',
        question: 'Are you leaving this slot?',
        confirmLabel: "YES, I'M LEAVING",
        confirmColor: AppColors.slotOccupied,
        onClose: () => Navigator.of(dialogContext).pop(),
        onConfirm: () async {
          final previousLabel = _confirmedSlotLabel;
          final previousId = _confirmedSlotId;
          final previousSection = _confirmedSectionKey;

          setState(() {
            _confirmedSlotLabel = null;
            _confirmedSlotId = null;
            _confirmedSectionKey = null;
            _showThankYouBanner = true;
          });
          _liveUpdates.notifyListeners();
          Navigator.of(dialogContext).pop();

          // Free the slot up in Firebase so it goes back to vacant/green
          // for everyone watching the live map, and clears this
          // account's user_slots entry.
          final success = await _writeSlotFree(
            sectionKey: sectionKey,
            slotId: slot.id,
          );

          if (!success && mounted) {
            // Don't tell the driver they've left a slot Firebase still
            // has marked as theirs.
            setState(() {
              _confirmedSlotLabel = previousLabel;
              _confirmedSlotId = previousId;
              _confirmedSectionKey = previousSection;
              _showThankYouBanner = false;
            });
            _liveUpdates.notifyListeners();
            return;
          }

          _thankYouTimer?.cancel();
          _thankYouTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _showThankYouBanner = false);
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Parking map',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            '212 stalls monitored • Live',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),

          // Mall-wide totals — sits where the "Suggested for you" banner
          // used to be. The per-visit "Suggested for you" / "Current
          // parking slot" banner and the "I am with a PWD" toggle now
          // live on each section's dedicated live map screen instead
          // (see _SectionLiveMapScreen), alongside that section's grid.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: _StatsRow(
              sections: _sections.values.toList(),
              confirmedSlotId: _confirmedSlotId,
              liveOccupancy: _liveOccupancy,
              pwdSlotsVisible: _pwdSlotsVisible,
            ),
          ),
          const SizedBox(height: 16),

          // Compass-style overview mirroring the mall's real floor plan:
          // Back along the top, Side along the right, Front along the
          // bottom, with the store footprint in between. Each zone box
          // renders one small colored rectangle per actual slot, using
          // live Firebase occupancy. Tapping a zone pushes a dedicated
          // full-screen live map for that section (_openSectionLiveMap)
          // instead of scrolling to the inline grid below.
          // PWD-reserved slots are hidden from the dots/count entirely
          // unless pwdSlotsVisible is true.
          _ParkingCompassOverview(
            sections: _sections,
            selectedKey: _selectedSection,
            confirmedSlotId: _confirmedSlotId,
            liveOccupancy: _liveOccupancy,
            pwdSlotsVisible: _pwdSlotsVisible,
            onZoneTap: _openSectionLiveMap,
          ),

          // The inline per-section "SECTION PARKING — LIVE MAP" grid
          // used to live here, but it's been removed: tapping a zone in
          // the compass overview above now pushes a dedicated full-screen
          // live map for that section (see _openSectionLiveMap /
          // _SectionLiveMapScreen), so keeping a copy here just
          // duplicated it.

          // Generate QR button intentionally removed from here.
          // It now belongs in the parent Scaffold's bottomNavigationBar
          // (see ParkingMapScreen above, or home_screen.dart) so it
          // stays fixed on screen instead of scrolling with this content.
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Full-screen live map for a single section (Front/Side/Back), pushed
/// when a compass zone box is tapped (see
/// _ParkingMapBodyState._openSectionLiveMap). Renders the same
/// "Suggested for you" / "Current parking slot" banner and "I am with
/// a PWD" toggle that used to sit at the top of the main map screen,
/// followed by the per-sub-area grid the old inline
/// "SECTION PARKING — LIVE MAP" block showed — all on its own route
/// with its own AppBar.
///
/// This screen doesn't own a Firebase subscription — it re-reads live
/// state from the parent [ParkingMapBody] through the getter closures
/// below, and rebuilds whenever [listenable] fires (i.e. whenever the
/// parent's occupancy/confirmed-slot/pwd-visibility state changes).
class _SectionLiveMapScreen extends StatelessWidget {
  final ParkingSection section;
  final Listenable listenable;
  final String? Function() getConfirmedSlotId;
  final String? Function() getConfirmedSlotLabel;
  final bool Function() getShowThankYou;
  final Map<String, bool> Function() getLiveOccupancy;
  final bool Function() getPwdSlotsVisible;
  // Whether to offer the "I am with a PWD" checkbox at all — false for
  // accounts already registered as PWD themselves (see
  // _ParkingMapBodyState._isAccountPwd).
  final bool Function() getShowPwdToggle;
  final bool Function() getWithPwd;
  final ValueChanged<bool> onWithPwdChanged;
  final void Function(ParkingSlot slot) onSlotTap;
  final void Function(ParkingSlot slot) onConfirmedSlotTap;

  const _SectionLiveMapScreen({
    required this.section,
    required this.listenable,
    required this.getConfirmedSlotId,
    required this.getConfirmedSlotLabel,
    required this.getShowThankYou,
    required this.getLiveOccupancy,
    required this.getPwdSlotsVisible,
    required this.getShowPwdToggle,
    required this.getWithPwd,
    required this.onWithPwdChanged,
    required this.onSlotTap,
    required this.onConfirmedSlotTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primaryBlue,
        elevation: 0,
        title: Text(
          '${section.label} parking',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
        ),
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: listenable,
          builder: (context, _) {
            final confirmedSlotId = getConfirmedSlotId();
            final liveOccupancy = getLiveOccupancy();
            final pwdSlotsVisible = getPwdSlotsVisible();
            final showPwdToggle = getShowPwdToggle();

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SuggestedSlotBanner(
                    section: section,
                    liveOccupancy: liveOccupancy,
                    confirmedSlotId: confirmedSlotId,
                    confirmedSlotLabel: getConfirmedSlotLabel(),
                    showThankYou: getShowThankYou(),
                  ),
                  if (showPwdToggle) ...[
                    const SizedBox(height: 12),
                    _PwdVisibilityToggle(
                      value: getWithPwd(),
                      onChanged: onWithPwdChanged,
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text(
                    '${section.label.toUpperCase()} PARKING — LIVE MAP',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (int i = 0; i < section.subAreas.length; i++) ...[
                    if (i > 0) const SizedBox(height: 20),
                    Text(
                      section.subAreas[i].label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ParkingGrid(
                      subArea: section.subAreas[i],
                      sectionLabel: section.label,
                      confirmedSlotId: confirmedSlotId,
                      liveOccupancy: liveOccupancy,
                      pwdSlotsVisible: pwdSlotsVisible,
                      onSlotTap: onSlotTap,
                      onConfirmedSlotTap: onConfirmedSlotTap,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Picks the [limit] lowest-numbered vacant slots in [section] for the
/// "Suggested for you" banner — e.g. F1/F2/F3 for Front, S1/S2/S3 for
/// Side, BT1/BT2/BT3 for Back's first sub-area with a vacancy, always
/// skipping whichever ones are already occupied (live Firebase status
/// taking priority over the static demo flag, same as everywhere else
/// in this screen). PWD-reserved slots are never suggested here,
/// regardless of PWD-visibility settings — this banner is a general
/// "here's a good open spot" suggestion, not a PWD-slot picker.
List<String> _suggestedSlotIds({
  required ParkingSection section,
  required Map<String, bool> liveOccupancy,
  String? confirmedSlotId,
  int limit = 3,
}) {
  bool isVacant(ParkingSlot s) {
    if (s.isPwd) return false;
    if (s.id == confirmedSlotId) return false;
    return !(liveOccupancy[s.id] ?? s.isOccupied);
  }

  int numericSuffix(String id) =>
      int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  final vacant = section.slots.where(isVacant).toList()
    ..sort((a, b) => numericSuffix(a.id).compareTo(numericSuffix(b.id)));

  return vacant.take(limit).map((s) => s.id).toList();
}

class _SuggestedSlotBanner extends StatelessWidget {
  final ParkingSection section;
  final Map<String, bool> liveOccupancy;
  final String? confirmedSlotId;
  final String? confirmedSlotLabel;
  final bool showThankYou;
  const _SuggestedSlotBanner({
    required this.section,
    required this.liveOccupancy,
    this.confirmedSlotId,
    this.confirmedSlotLabel,
    this.showThankYou = false,
  });

  @override
  Widget build(BuildContext context) {
    final isConfirmed = confirmedSlotLabel != null;

    // Three banner states: thank-you (just left) > confirmed (parked) >
    // suggested (default).
    final String eyebrow;
    final String message;
    final Color accentColor;
    if (showThankYou) {
      eyebrow = 'THANK YOU';
      message = 'Drive safe — come back soon!';
      accentColor = AppColors.slotAvailable;
    } else if (isConfirmed) {
      eyebrow = 'CURRENT PARKING SLOT';
      message = confirmedSlotLabel!;
      accentColor = AppColors.primaryBlue;
    } else {
      eyebrow = 'SUGGESTED FOR YOU';
      final suggestedIds = _suggestedSlotIds(
        section: section,
        liveOccupancy: liveOccupancy,
        confirmedSlotId: confirmedSlotId,
      );
      message = suggestedIds.isEmpty
          ? '${section.label} section is full right now'
          : '${section.label} section — ${suggestedIds.join(', ')}';
      accentColor = AppColors.primaryBlue;
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Container(
        key: ValueKey('$eyebrow-$message'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: showThankYou ? accentColor : AppColors.border,
            width: showThankYou ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              eyebrow,
              style: TextStyle(
                fontSize: 11,
                color: showThankYou ? accentColor : AppColors.textSecondary,
                fontWeight: showThankYou ? FontWeight.w700 : FontWeight.w400,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Session-only checkbox offered to non-PWD accounts: "I am with a
/// PWD". Checking it reveals PWD-reserved slots for this visit without
/// touching the account's registration status. Deliberately the
/// opposite of persisting it — letting anyone permanently unlock PWD
/// slots with a single tap would defeat the point of gating them.
class _PwdVisibilityToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _PwdVisibilityToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: AppColors.primaryBlue,
        dense: true,
        title: const Text(
          'I am with a PWD',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: const Text(
          "Not registered as PWD yourself, but travelling with someone who is — reveal PWD slots for this visit.",
          style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// Compass-style overview of the whole mall, laid out to mirror the real
/// floor plan (Back along the top, Side along the right edge, Front
/// along the bottom, store footprint in the middle). Each zone box shows
/// one small colored rectangle per actual slot in that section — an
/// exact, at-a-glance count rather than a simplified sample, driven by
/// live Firebase occupancy. Tapping a zone box hands off to [onZoneTap],
/// which pushes a dedicated full-screen live map for that section.
/// PWD-reserved slots are excluded entirely unless [pwdSlotsVisible].
class _ParkingCompassOverview extends StatelessWidget {
  final Map<String, ParkingSection> sections;
  final String selectedKey;
  final String? confirmedSlotId;
  final Map<String, bool> liveOccupancy;
  final bool pwdSlotsVisible;
  final ValueChanged<String> onZoneTap;

  const _ParkingCompassOverview({
    required this.sections,
    required this.selectedKey,
    required this.onZoneTap,
    required this.liveOccupancy,
    required this.pwdSlotsVisible,
    this.confirmedSlotId,
  });

  @override
  Widget build(BuildContext context) {
    final back = sections['back']!;
    final front = sections['front']!;
    final side = sections['side']!;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'MALL PARKING OVERVIEW',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),

          // Back — top edge of the floor plan.
          _CompassZoneBox(
            label: 'Back',
            section: back,
            isActive: selectedKey == 'back',
            confirmedSlotId: confirmedSlotId,
            liveOccupancy: liveOccupancy,
            pwdSlotsVisible: pwdSlotsVisible,
            onTap: () => onZoneTap('back'),
          ),
          const SizedBox(height: 8),

          // Store footprint (decorative, non-interactive) + Side — right
          // edge of the floor plan, matching the driveway-then-side-lot
          // arrangement in the actual mall.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
                      'WALTERMART MALL',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textTertiary,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: _CompassZoneBox(
                    label: 'Side',
                    section: side,
                    isActive: selectedKey == 'side',
                    confirmedSlotId: confirmedSlotId,
                    liveOccupancy: liveOccupancy,
                    pwdSlotsVisible: pwdSlotsVisible,
                    onTap: () => onZoneTap('side'),
                    verticalLine: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Front — bottom edge of the floor plan.
          _CompassZoneBox(
            label: 'Front',
            section: front,
            isActive: selectedKey == 'front',
            confirmedSlotId: confirmedSlotId,
            liveOccupancy: liveOccupancy,
            pwdSlotsVisible: pwdSlotsVisible,
            onTap: () => onZoneTap('front'),
          ),
        ],
      ),
    );
  }
}

/// One tappable zone box within the compass overview. Renders a header
/// (label + available/total) and a wrapped grid of small rectangles —
/// one per slot in [section] — colored green/red for available/occupied,
/// based on live Firebase occupancy (falling back to the static demo
/// flag only for slots Firebase hasn't reported on yet). PWD-reserved
/// slots are dropped from both the dots and the count unless
/// [pwdSlotsVisible] is true.
class _CompassZoneBox extends StatelessWidget {
  final String label;
  final ParkingSection section;
  final bool isActive;
  final String? confirmedSlotId;
  final Map<String, bool> liveOccupancy;
  final bool pwdSlotsVisible;
  final VoidCallback onTap;
  // When true, renders occupancy as one continuous vertical line of
  // stacked segments instead of a wrapped grid of dots — used for
  // sections that are physically a single row of slots (e.g. Side),
  // so the overview mirrors the real layout.
  final bool verticalLine;

  const _CompassZoneBox({
    required this.label,
    required this.section,
    required this.isActive,
    required this.onTap,
    required this.liveOccupancy,
    required this.pwdSlotsVisible,
    this.confirmedSlotId,
    this.verticalLine = false,
  });

  bool _isOccupied(ParkingSlot s) {
    if (s.id == confirmedSlotId) return true;
    return liveOccupancy[s.id] ?? s.isOccupied;
  }

  @override
  Widget build(BuildContext context) {
    // Hide PWD-reserved slots entirely from the overview (dots + counts)
    // unless this driver is PWD-registered or checked "I am with a PWD".
    final slots = pwdSlotsVisible
        ? section.slots
        : section.slots.where((s) => !s.isPwd).toList();
    final occupiedCount = slots.where(_isOccupied).length;
    final available = slots.length - occupiedCount;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryBlue.withValues(alpha: 0.06)
              : AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? AppColors.primaryBlue : AppColors.border,
            width: isActive ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: isActive
                        ? AppColors.primaryBlue
                        : AppColors.textPrimary,
                  ),
                ),
                Text(
                  '$available/${slots.length}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            verticalLine
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: slots
                          .map((s) {
                            final occupied = _isOccupied(s);
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: occupied
                                      ? AppColors.slotOccupied
                                      : AppColors.slotAvailable,
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  )
                : Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: slots
                        .map((s) {
                          final occupied = _isOccupied(s);
                          return Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: occupied
                                  ? AppColors.slotOccupied
                                  : AppColors.slotAvailable,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          );
                        })
                        .toList(),
                  ),
          ],
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final List<ParkingSection> sections;
  final String? confirmedSlotId;
  // Live Firebase occupancy — used so Total/Available/Unavailable reflect
  // what's actually in the database instead of the static demo data
  // (which marks every slot as available).
  final Map<String, bool> liveOccupancy;
  // PWD-reserved slots are excluded from all three counts unless true.
  final bool pwdSlotsVisible;
  const _StatsRow({
    required this.sections,
    required this.liveOccupancy,
    required this.pwdSlotsVisible,
    this.confirmedSlotId,
  });

  bool _isOccupied(ParkingSlot s) {
    if (s.id == confirmedSlotId) return true;
    return liveOccupancy[s.id] ?? s.isOccupied;
  }

  @override
  Widget build(BuildContext context) {
    final allSlots = sections
        .expand((section) => section.subAreas)
        .expand((a) => [...a.leftColumn, ...a.rightColumn])
        .where((s) => pwdSlotsVisible || !s.isPwd)
        .toList();
    final occupied = allSlots.where(_isOccupied).length;
    final available = allSlots.length - occupied;

    return Row(
      children: [
        _StatCard(label: 'Total', value: '${allSlots.length}', color: AppColors.textPrimary),
        const SizedBox(width: 10),
        _StatCard(label: 'Available', value: '$available', color: AppColors.slotAvailable),
        const SizedBox(width: 10),
        _StatCard(label: 'Unavailable', value: '$occupied', color: AppColors.slotOccupied),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        _LegendDot(color: AppColors.slotAvailable, label: 'Available'),
        SizedBox(width: 10),
        _LegendDot(color: AppColors.slotOccupied, label: 'Unavailable'),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

/// Renders a sub-area's slots as two columns split by a dashed drive lane,
/// matching the physical layout of the parking area. Available slots are
/// tappable; occupied slots are not (nothing to confirm there). Occupied
/// status comes from live Firebase data via [liveOccupancy], falling back
/// to the slot's static isOccupied flag only if Firebase hasn't reported
/// on that slot yet.
///
/// [confirmedSlotId], if set, forces that one tile to render as occupied
/// (red) and wraps it in a highlighted ring so the driver can spot their
/// own slot at a glance.
///
/// PWD-reserved slots are dropped from both columns entirely — not just
/// grayed out — unless [pwdSlotsVisible] is true, so a non-PWD driver
/// who hasn't checked "I am with a PWD" can't see or tap them at all.
class _ParkingGrid extends StatelessWidget {
  final ParkingSubArea subArea;
  final String sectionLabel;
  final String? confirmedSlotId;
  final Map<String, bool> liveOccupancy;
  final bool pwdSlotsVisible;
  final void Function(ParkingSlot slot) onSlotTap;
  final void Function(ParkingSlot slot) onConfirmedSlotTap;

  const _ParkingGrid({
    required this.subArea,
    required this.sectionLabel,
    required this.onSlotTap,
    required this.onConfirmedSlotTap,
    required this.liveOccupancy,
    required this.pwdSlotsVisible,
    this.confirmedSlotId,
  });

  Widget _buildTile(ParkingSlot slot) {
    print("${slot.id} -> ${liveOccupancy[slot.id]}");
    final isConfirmed = confirmedSlotId != null && slot.id == confirmedSlotId;
    final isOccupied =
        isConfirmed || (liveOccupancy[slot.id] ?? slot.isOccupied);

    final effectiveSlot =
        ParkingSlot(id: slot.id, isOccupied: isOccupied, isPwd: slot.isPwd);

    Widget tile = ParkingStallTile(slot: effectiveSlot);

    if (isConfirmed) {
      // The user's own slot: tapping it now asks if they're leaving,
      // instead of being a dead end like other occupied slots.
      tile = _ConfirmedSlotHighlight(child: tile);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onConfirmedSlotTap(slot),
        child: tile,
      );
    }

    // Other occupied slots stay non-tappable; only available slots open
    // the park-confirmation dialog.
    if (isOccupied) return tile;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSlotTap(slot),
      child: tile,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Drop PWD-reserved slots from both columns entirely (not just
    // grayed out) unless this driver is PWD-registered or checked
    // "I am with a PWD".
    final leftSlots = pwdSlotsVisible
        ? subArea.leftColumn
        : subArea.leftColumn.where((s) => !s.isPwd).toList();
    final rightSlots = pwdSlotsVisible
        ? subArea.rightColumn
        : subArea.rightColumn.where((s) => !s.isPwd).toList();

    // Side-style sub-areas are laid out as a single line of slots against
    // the mall wall, with the driveway running alongside — not split
    // across a center drive lane like Front/Back. Detected by an empty
    // leftColumn (after PWD filtering), which is how the single-line
    // sub-areas are defined.
    final isLinear = leftSlots.isEmpty && rightSlots.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Align(
            alignment: Alignment.centerRight,
            child: _LegendRow(),
          ),
          const SizedBox(height: 12),
          if (isLinear)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _MallWallBar(label: 'WALTERMART MALL'),
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: 160,
                        child: Column(
                          children: rightSlots
                              .map((slot) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 4),
                                    child: _buildTile(slot),
                                  ))
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  const _DrivewayLane(label: 'DRIVEWAY'),
                ],
              ),
            )
          else
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      children: leftSlots
                          .map((slot) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: _buildTile(slot),
                              ))
                          .toList(),
                    ),
                  ),
                  const _DriveLane(),
                  Expanded(
                    child: Column(
                      children: rightSlots
                          .map((slot) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: _buildTile(slot),
                              ))
                          .toList(),
                    ),
                  ),
                  // Front backs directly onto the mall, so it gets the
                  // same wall bar as the linear (Side) layout — pinned
                  // to the right edge here since Front's rightColumn is
                  // the side closest to the building.
                  if (sectionLabel == 'Front') ...[
                    const SizedBox(width: 10),
                    const _MallWallBar(label: 'WALTERMART MALL'),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Vertical wall bar shown alongside a single-line sub-area's slots
/// (e.g. Side parking), labeling the mall building the slots back onto.
class _MallWallBar extends StatelessWidget {
  final String label;
  const _MallWallBar({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 65,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      alignment: Alignment.center,
      child: RotatedBox(
        quarterTurns: 3,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.textTertiary,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Vertical dashed lane shown alongside a single-line sub-area's slots
/// (e.g. Side parking), labeling where cars actually drive past the
/// slots — distinct from the mall wall on the opposite side.
class _DrivewayLane extends StatelessWidget {
  final String label;
  const _DrivewayLane({required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          const _DashedVerticalLine(),
          Center(
            child: RotatedBox(
              quarterTurns: 3,
              child: Container(
                color: AppColors.cardBackground,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps a confirmed slot's tile with a bold ring + glow and a small
/// "YOU" badge so it's immediately visible against the rest of the grid.
class _ConfirmedSlotHighlight extends StatelessWidget {
  final Widget child;
  const _ConfirmedSlotHighlight({required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primaryBlue, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withValues(alpha: 0.35),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        ),
        Positioned(
          top: -6,
          right: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 3),
              ],
            ),
            child: const Text(
              'YOU',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DriveLane extends StatelessWidget {
  const _DriveLane();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 75,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      child: const _DashedVerticalLine(),
    );
  }
}

class _DashedVerticalLine extends StatelessWidget {
  const _DashedVerticalLine();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedLinePainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.textTertiary
      ..strokeWidth = 1.5;
    const dashHeight = 5.0;
    const dashSpace = 4.0;
    final height = size.height.isFinite ? size.height : 0.0;
    double y = 0;
    final x = size.width / 2;
    while (y < height) {
      canvas.drawLine(Offset(x, y), Offset(x, y + dashHeight), paint);
      y += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Shared confirmation popup, used both when the user taps an available
/// slot (asking if they're parked there) and when they tap their own
/// confirmed slot (asking if they're leaving).
class _ParkingDialog extends StatelessWidget {
  final String headerTitle;
  final String subtitleText;
  final String question;
  final String confirmLabel;
  final Color confirmColor;
  final VoidCallback onClose;
  final VoidCallback onConfirm;

  const _ParkingDialog({
    required this.headerTitle,
    required this.subtitleText,
    required this.question,
    required this.confirmLabel,
    required this.confirmColor,
    required this.onClose,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Blue header bar with title + close (X) button.
            Container(
              width: double.infinity,
              color: AppColors.primaryBlue,
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      headerTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: const Icon(Icons.close, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            // Body: slot label, question, and action buttons.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                children: [
                  Text(
                    subtitleText,
                    style: const TextStyle(
                      color: AppColors.primaryBlue,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    question,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onClose,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primaryBlue,
                            side: const BorderSide(
                                color: AppColors.primaryBlue, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'CLOSE',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: onConfirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: confirmColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            confirmLabel,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
