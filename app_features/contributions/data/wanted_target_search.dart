import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';

/// "Send something else" search over only what's missing: the entries in the published wanted list
/// (data/_wanted.json), each with what it lacks. Falls back to [_all] (the whole catalog on the phone) only when
/// the list isn't set up or can't be loaded, so the page keeps working offline.
class WantedTargetSearch implements ContributionTargetSearch {
  const WantedTargetSearch(this._wanted, this._all);

  final WantedSource _wanted;
  final ContributionTargetSearch _all;

  /// Sheets that aren't parts (everything else in the list is a part sheet: blades, ratchets, burstLayers ...).
  static const _notParts = {'bladers', 'products', 'accessories', 'tcgCards', 'tcgSets', 'productContents',
      'stockCombos'};

  static bool inGroup(String group, String sheet) => switch (group) {
        'parts' => !_notParts.contains(sheet),
        'bladers' || 'products' || 'accessories' => sheet == group,
        _ => false,
      };

  @override
  Future<List<ContributionTarget>> search(String type, String query, {int limit = 30}) async {
    if (!_wanted.isConfigured) return _all.search(type, query, limit: limit);
    final WantedList list;
    try {
      list = await _wanted.load();
    } on ContributionException {
      return _all.search(type, query, limit: limit);
    }
    final q = query.trim().toLowerCase();
    return [
      for (final i in list.items)
        if (inGroup(type, i.sheet) &&
            (q.isEmpty || '${i.name} ${i.code} ${i.variant ?? ''}'.toLowerCase().contains(q)))
          ContributionTarget(
            type: i.sheet,
            id: i.id,
            name: [i.name, if (i.variant != null) i.variant!, if (i.code.isNotEmpty) i.code].join(' · '),
            missing: [for (final f in i.missing) list.field(i.sheet, f)?.label ?? f],
          ),
    ].take(limit).toList();
  }
}
