import 'tcn_packet.dart';

/// Which slots share a motor in a cabinet of [rows] × [columns] slots,
/// numbered 1 to [slotCount] row by row.
///
/// A double slot (one wide spiral) joins slot N and N+1 in the same row onto
/// lane N's motor, so slot N+1 has no motor of its own. The board cannot
/// report its pairs: this map must match what was set on the board.
///
/// Immutable. [motorFor] is O(1).
final class SlotLayout {
  /// A layout with [pairStarts] (the first slot of each double slot; empty
  /// means every slot has its own motor).
  ///
  /// Throws [ArgumentError] when the size is invalid (more than
  /// [tcnMaxLane] slots, or fewer than 1 row or 2 columns), or when a pair
  /// start is not a slot, is the last slot of its row, or overlaps another
  /// pair. A wrong map would turn the wrong motor, so it is never accepted.
  SlotLayout({
    this.rows = 6,
    this.columns = 10,
    Iterable<int> pairStarts = const [],
  }) : pairStarts = _validate(rows, columns, pairStarts);

  /// Rows of slots.
  final int rows;

  /// Slots per row.
  final int columns;

  /// The first slot of each double slot. Unmodifiable.
  final Set<int> pairStarts;

  /// All slots, [rows] × [columns].
  int get slotCount => rows * columns;

  /// Whether [slot] is in 1..[slotCount].
  bool isSlot(int slot) => slot >= 1 && slot <= slotCount;

  /// Whether [slot] can start a double slot: it exists and is not the last
  /// in its row.
  bool canStartPair(int slot) => isSlot(slot) && slot % columns != 0;

  /// The pair starts that make [row] (1..[rows]) all double, for example
  /// row 2 of a 10-column cabinet: 11, 13, 15, 17, 19. Throws [RangeError]
  /// for a row outside the cabinet.
  List<int> rowPairStarts(int row) {
    RangeError.checkValueInInterval(row, 1, rows, 'row');
    final first = (row - 1) * columns + 1;
    return [
      for (var s = first; s + 1 < first + columns; s += 2) s,
    ];
  }

  /// The lane to send to `TcnBoard.dispense` for [slot]: the second half of a
  /// pair uses the first half's motor. Throws [RangeError] for a slot
  /// outside 1..[slotCount].
  int motorFor(int slot) {
    RangeError.checkValueInInterval(slot, 1, slotCount, 'slot');
    return pairStarts.contains(slot - 1) ? slot - 1 : slot;
  }

  @override
  bool operator ==(Object other) =>
      other is SlotLayout &&
      other.rows == rows &&
      other.columns == columns &&
      other.pairStarts.length == pairStarts.length &&
      other.pairStarts.containsAll(pairStarts);

  @override
  int get hashCode =>
      Object.hash(rows, columns, Object.hashAllUnordered(pairStarts));

  /// For logs, for example `SlotLayout(6x10, pairs: 11+12, 13+14)`.
  @override
  String toString() {
    final pairs = [for (final s in pairStarts.toList()..sort()) '$s+${s + 1}'];
    return 'SlotLayout(${rows}x$columns, pairs: '
        '${pairs.isEmpty ? 'none' : pairs.join(', ')})';
  }

  static Set<int> _validate(int rows, int columns, Iterable<int> starts) {
    if (rows < 1 || columns < 2 || rows * columns > tcnMaxLane) {
      throw ArgumentError('A cabinet is at least 1 row of 2 slots and at most '
          '$tcnMaxLane slots, not ${rows}x$columns');
    }
    final count = rows * columns;
    final result = <int>{};
    for (final s in starts) {
      if (s < 1 || s > count) {
        throw ArgumentError.value(s, 'pairStarts', 'is not a slot (1-$count)');
      }
      if (s % columns == 0) {
        throw ArgumentError.value(
            s, 'pairStarts', 'is the last slot in its row');
      }
      if (result.contains(s) ||
          result.contains(s - 1) ||
          result.contains(s + 1)) {
        throw ArgumentError.value(s, 'pairStarts', 'overlaps another pair');
      }
      result.add(s);
    }
    return Set.unmodifiable(result);
  }
}
