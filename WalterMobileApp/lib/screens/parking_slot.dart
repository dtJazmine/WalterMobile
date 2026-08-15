/// Represents a single parking slot's state.
/// In production this maps directly to a Firebase Realtime Database
/// document, e.g. /slots/{floor}/{slotId} -> { sensor, confirmed, isPwd, column }
class ParkingSlot {
  final String id;
  final bool isOccupied;
  final bool isPwd;

  const ParkingSlot({
    required this.id,
    required this.isOccupied,
    this.isPwd = false,
  });

  factory ParkingSlot.fromMap(String id, Map<String, dynamic> map) {
    return ParkingSlot(
      id: id,
      isOccupied: map['sensor'] == 'occupied',
      isPwd: map['isPwd'] == true,
    );
  }
}

/// One selectable sub-area within a section, e.g. "Front - Left side
/// parking". [leftColumn] and [rightColumn] are explicit, top-to-bottom,
/// to mirror the real physical layout of the mall rather than an even
/// numeric split.
class ParkingSubArea {
  final String key;
  final String label;
  final List<ParkingSlot> leftColumn;
  final List<ParkingSlot> rightColumn;

  const ParkingSubArea({
    required this.key,
    required this.label,
    required this.leftColumn,
    required this.rightColumn,
  });

  List<ParkingSlot> get slots => [...leftColumn, ...rightColumn];
}

/// Represents one section of the parking area (Front, Side, Back).
/// A section is made up of one or more [subAreas] \u2014 e.g. Front splits
/// into "Left side parking" and "Right side parking", each with its own
/// live map. Totals (total/available/occupied) are computed across all
/// sub-areas combined, while the live map shows one sub-area at a time.
class ParkingSection {
  final String key;
  final String label;
  final List<ParkingSubArea> subAreas;

  const ParkingSection({
    required this.key,
    required this.label,
    required this.subAreas,a
  });

  List<ParkingSlot> get slots =>
      subAreas.expand((area) => area.slots).toList();

  int get total => slots.length;
  int get available => slots.where((s) => !s.isOccupied).length;
  int get occupied => slots.where((s) => s.isOccupied).length;
}
