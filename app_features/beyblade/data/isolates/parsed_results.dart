/// Catalog sheets this feature reads when the catalog has them (never required, so older releases and
/// bundles still apply): the stock combos of each product and the bladers who use parts in the show.
const kBeybladeExtraSheets = <String>['stockCombos', 'bladers'];

class ParsedFullBundle {
  const ParsedFullBundle({
    required this.blades,
    required this.ratchets,
    required this.bits,
    required this.lockChips,
    required this.overBlades,
    required this.metalBlades,
    required this.mainBlades,
    required this.assistBlades,
    required this.products,
    required this.accessories,
    required this.productContents,
    this.stockCombos = const [],
    this.bladers = const [],
  });

  final List<Map<String, dynamic>> blades;
  final List<Map<String, dynamic>> ratchets;
  final List<Map<String, dynamic>> bits;
  final List<Map<String, dynamic>> lockChips;
  final List<Map<String, dynamic>> overBlades;
  final List<Map<String, dynamic>> metalBlades;
  final List<Map<String, dynamic>> mainBlades;
  final List<Map<String, dynamic>> assistBlades;
  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> accessories;

  /// Not part of totalRecords -- these rows describe box CONTENTS, not
  /// catalog entries of their own, so counting them alongside real parts
  /// would inflate the number without meaning the same thing.
  final List<Map<String, dynamic>> productContents;

  /// Optional sheets ([kBeybladeExtraSheets]); empty when the catalog doesn't have them. Like
  /// productContents, not counted in totalRecords.
  final List<Map<String, dynamic>> stockCombos;
  final List<Map<String, dynamic>> bladers;

  int get totalRecords =>
      blades.length +
      ratchets.length +
      bits.length +
      lockChips.length +
      overBlades.length +
      metalBlades.length +
      mainBlades.length +
      assistBlades.length +
      products.length +
      accessories.length;
}
