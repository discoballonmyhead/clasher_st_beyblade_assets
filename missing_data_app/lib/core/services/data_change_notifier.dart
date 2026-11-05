import 'dart:async';

/// What changed, so listeners can refresh only what they show.
/// [rowsEdited] = the row editor changed its own row; [filled] = many rows changed at once (auto-fill);
/// [structureChanged] = a row or a column was added.
enum DataChange { workbookOpened, rowsEdited, filled, structureChanged, saved, undone, wikiFinished }

/// Cubits that change data announce it here; cubits that show data listen and refresh.
/// Keeps cubits independent of each other.
class DataChangeNotifier {
  final _controller = StreamController<DataChange>.broadcast();

  Stream<DataChange> get stream => _controller.stream;

  void notify(DataChange change) => _controller.add(change);

  Future<void> dispose() => _controller.close();
}
