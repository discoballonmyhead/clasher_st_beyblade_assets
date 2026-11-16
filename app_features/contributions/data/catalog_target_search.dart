import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';

/// Searches the beyblade catalog already on the phone (parts, bladers, products, accessories).
class CatalogTargetSearch implements ContributionTargetSearch {
  const CatalogTargetSearch(this._repo);

  final BeybladeDataRepo _repo;

  @override
  Future<List<ContributionTarget>> search(String type, String query, {int limit = 30}) async {
    final q = query.trim().toLowerCase();
    bool hit(String s) => q.isEmpty || s.toLowerCase().contains(q);
    switch (type) {
      case 'parts':
        if (q.isEmpty) return const [];
        return [
          for (final p in (await _repo.searchBeyParts(q)).take(limit))
            ContributionTarget(type: partSheetKey(p), id: p.dataId, name: _partLabel(p)),
        ];
      case 'bladers':
        return [
          for (final b in (await _repo.getAllBladers()).where((b) => hit(b.name)).take(limit))
            ContributionTarget(type: 'bladers', id: b.bladerId, name: b.name),
        ];
      case 'products':
        return [
          for (final p in (await _repo.getAllProducts())
              .where((p) => hit(p.productName) || hit(p.sku ?? ''))
              .take(limit))
            ContributionTarget(type: 'products', id: p.productId, name: p.productName),
        ];
      case 'accessories':
        return [
          for (final a in (await _repo.getAllAccessories()).where((a) => hit(a.name)).take(limit))
            ContributionTarget(type: 'accessories', id: a.dataId, name: a.name),
        ];
      default:
        return const [];
    }
  }

  static String _partLabel(BeybladePart p) =>
      [p.name, if (p.variantLabel != null) p.variantLabel!, p.code].join(' · ');
}

/// The catalog sheet a part belongs to (what the submissions sheet and Clasher Studio use).
String partSheetKey(BeybladePart p) => switch (p) {
      Blade() => 'blades',
      Ratchet() => 'ratchets',
      Bit() => 'bits',
      LockChip() => 'lockChips',
      OverBlade() => 'overBlades',
      MetalBlade() => 'metalBlades',
      MainBlade() => 'mainBlades',
      AssistBlade() => 'assistBlades',
      _ => 'other',
    };
