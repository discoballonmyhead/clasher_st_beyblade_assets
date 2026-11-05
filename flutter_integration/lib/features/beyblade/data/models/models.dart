import 'package:clasher_st/core/utils/sheet_row_parsing.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';

// Consolidated data models. `dataID` is the real key everywhere; `code`
// isn't unique. Stat/enum fields are stored as raw sheet strings, parsed
// into real types only in toEntity() — keeps this layer immune to enum
// drift across app versions. isIncomplete reads the packaged
// `incompleteData` field, present on every tracked sheet now.
//
// Field names below match the PACKAGER's JSON output, not the raw
// spreadsheet column names — the packager already renamed image/
// minifiedImage to imageUrl/imageHash/minifiedImageUrl/minifiedImageHash
// and extracted the actual files, so these models parse packaged JSON,
// not spreadsheet cells directly.

/// Parses the fields every part row shares (the identity/variant/
/// manufacturer/hobby columns plus both image pairs) -- composed into
/// every part model below rather than duplicated eight times. Mirrors
/// _TypedStatPartModel's existing "small parsing helper" pattern.
class _SharedPartFieldsModel {
  _SharedPartFieldsModel(Map<String, dynamic> row)
      : dataId = requiredString(row, 'dataID'),
        parentPartId = nullableString(ciGet(row, 'parentPartId')),
        variantLabel = nullableString(ciGet(row, 'variantLabel')),
        manufacturer = requiredString(row, 'manufacturer'),
        hobbyName = requiredString(row, 'hobbyName'),
        hobbyGeneration = requiredString(row, 'hobbyGeneration'),
        code = requiredString(row, 'code'),
        name = requiredString(row, 'name'),
        edition = nullableString(ciGet(row, 'edition')),
        imageUrl = nullableString(ciGet(row, 'imageUrl')),
        imageHash = nullableString(ciGet(row, 'imageHash')),
        minifiedImageUrl = nullableString(ciGet(row, 'minifiedImageUrl')),
        minifiedImageHash = nullableString(ciGet(row, 'minifiedImageHash')),
        mass = parseDouble(ciGet(row, 'mass')) ?? 0,
        legalityRaw = requiredString(row, 'wbolegality'),
        isIncomplete = parseBool(ciGet(row, 'incompleteData'));

  final String dataId;
  final String? parentPartId;
  final String? variantLabel;
  final String manufacturer;
  final String hobbyName;
  final String hobbyGeneration;
  final String code;
  final String name;
  final String? edition;
  final String? imageUrl;
  final String? imageHash;
  final String? minifiedImageUrl;
  final String? minifiedImageHash;
  final double mass;
  final String legalityRaw;
  final bool isIncomplete;
}

// ── BLADE MODEL ─────────────────────────────────────────────────
class BladeModel {
  BladeModel.fromSheetJson(Map<String, dynamic> row)
      : _shared = _SharedPartFieldsModel(row),
        archetypeRaw = requiredString(row, 'type'),
        spinDirectionRaw = requiredString(row, 'spinDir'),
        attack = parseDouble(ciGet(row, 'attack')),
        defense = parseDouble(ciGet(row, 'defense')),
        stamina = parseDouble(ciGet(row, 'stamina')),
        hasIntegratedRatchet =
            parseBool(firstOf(row, ['integratedRathet', 'integratedRatchet'])),
        requiresSimpleRatchet = parseBool(ciGet(row, 'requiresSimpleRatchet'));

  final _SharedPartFieldsModel _shared;
  final String archetypeRaw, spinDirectionRaw;
  final double? attack, defense, stamina;
  final bool hasIntegratedRatchet;
  final bool requiresSimpleRatchet;

  Blade toEntity() => Blade(
        dataId: _shared.dataId,
        parentPartId: _shared.parentPartId,
        variantLabel: _shared.variantLabel,
        manufacturer: _shared.manufacturer,
        hobbyName: _shared.hobbyName,
        hobbyGeneration: _shared.hobbyGeneration,
        code: _shared.code,
        name: _shared.name,
        edition: _shared.edition,
        imageUrl: _shared.imageUrl,
        imageHash: _shared.imageHash,
        minifiedImageUrl: _shared.minifiedImageUrl,
        minifiedImageHash: _shared.minifiedImageHash,
        mass: _shared.mass,
        legality: WboLegality.parse(_shared.legalityRaw),
        isIncomplete: _shared.isIncomplete,
        archetype: BeybladeArchetype.parse(archetypeRaw),
        spinDirection: SpinDirection.parse(spinDirectionRaw),
        stats: StatBlock({
          StatKey.attack: StatSpread.parse(attack),
          StatKey.defense: StatSpread.parse(defense),
          StatKey.stamina: StatSpread.parse(stamina),
        }),
        hasIntegratedRatchet: hasIntegratedRatchet,
        requiresSimpleRatchet: requiresSimpleRatchet,
      );
}

// ── RATCHET MODEL ───────────────────────────────────────────────
class RatchetModel {
  RatchetModel.fromSheetJson(Map<String, dynamic> row)
      : _shared = _SharedPartFieldsModel(row),
        protrusions = parseInt(ciGet(row, 'protrusions')),
        heightMm = parseDouble(ciGet(row, 'heightMm')),
        attack = parseDouble(ciGet(row, 'attack')),
        defense = parseDouble(ciGet(row, 'defense')),
        stamina = parseDouble(ciGet(row, 'stamina')),
        isSimple = parseBool(ciGet(row, 'simpleRatchet'));

  final _SharedPartFieldsModel _shared;
  final int? protrusions;
  final double? heightMm, attack, defense, stamina;
  final bool isSimple;

  Ratchet toEntity() => Ratchet(
        dataId: _shared.dataId,
        parentPartId: _shared.parentPartId,
        variantLabel: _shared.variantLabel,
        manufacturer: _shared.manufacturer,
        hobbyName: _shared.hobbyName,
        hobbyGeneration: _shared.hobbyGeneration,
        code: _shared.code,
        name: _shared.name,
        edition: _shared.edition,
        imageUrl: _shared.imageUrl,
        imageHash: _shared.imageHash,
        minifiedImageUrl: _shared.minifiedImageUrl,
        minifiedImageHash: _shared.minifiedImageHash,
        mass: _shared.mass,
        legality: WboLegality.parse(_shared.legalityRaw),
        isIncomplete: _shared.isIncomplete,
        protrusions: protrusions,
        heightMm: heightMm,
        stats: StatBlock({
          StatKey.attack: StatSpread.parse(attack),
          StatKey.defense: StatSpread.parse(defense),
          StatKey.stamina: StatSpread.parse(stamina),
        }),
        isSimple: isSimple,
      );
}

// ── BIT MODEL ───────────────────────────────────────────────────
class BitModel {
  BitModel.fromSheetJson(Map<String, dynamic> row)
      : _shared = _SharedPartFieldsModel(row),
        baseName = requiredString(row, 'baseName'),
        movementStyleRaw = requiredString(row, 'movementStyle'),
        attackRaw = nullableString(ciGet(row, 'attack')),
        defenseRaw = nullableString(ciGet(row, 'defense')),
        staminaRaw = nullableString(ciGet(row, 'stamina')),
        dashRaw = nullableString(ciGet(row, 'dash')),
        burstResRaw = nullableString(ciGet(row, 'burstRes')),
        isTwoStat = parseBool(ciGet(row, 'twoStat')),
        hasIntegratedRatchet =
            parseBool(firstOf(row, ['integratedRathet', 'integratedRatchet']));

  final _SharedPartFieldsModel _shared;
  final String baseName, movementStyleRaw;
  final String? attackRaw, defenseRaw, staminaRaw, dashRaw, burstResRaw;
  final bool isTwoStat, hasIntegratedRatchet;

  Bit toEntity() => Bit(
        dataId: _shared.dataId,
        parentPartId: _shared.parentPartId,
        variantLabel: _shared.variantLabel,
        manufacturer: _shared.manufacturer,
        hobbyName: _shared.hobbyName,
        hobbyGeneration: _shared.hobbyGeneration,
        code: _shared.code,
        name: _shared.name,
        baseName: baseName,
        edition: _shared.edition,
        imageUrl: _shared.imageUrl,
        imageHash: _shared.imageHash,
        minifiedImageUrl: _shared.minifiedImageUrl,
        minifiedImageHash: _shared.minifiedImageHash,
        mass: _shared.mass,
        legality: WboLegality.parse(_shared.legalityRaw),
        isIncomplete: _shared.isIncomplete,
        movementStyle: BeybladeArchetype.parse(movementStyleRaw),
        stats: StatBlock({
          StatKey.attack: StatSpread.parse(attackRaw),
          StatKey.defense: StatSpread.parse(defenseRaw),
          StatKey.stamina: StatSpread.parse(staminaRaw),
          StatKey.dash: StatSpread.parse(dashRaw),
          StatKey.burstResistance: StatSpread.parse(burstResRaw),
        }),
        isTwoStat: isTwoStat,
        hasIntegratedRatchet: hasIntegratedRatchet,
      );
}

// ── LOCK CHIP MODEL ─────────────────────────────────────────────
/// No stat columns on this sheet.
class LockChipModel {
  LockChipModel.fromSheetJson(Map<String, dynamic> row)
      : _shared = _SharedPartFieldsModel(row);

  final _SharedPartFieldsModel _shared;

  LockChip toEntity() => LockChip(
        dataId: _shared.dataId,
        parentPartId: _shared.parentPartId,
        variantLabel: _shared.variantLabel,
        manufacturer: _shared.manufacturer,
        hobbyName: _shared.hobbyName,
        hobbyGeneration: _shared.hobbyGeneration,
        code: _shared.code,
        name: _shared.name,
        edition: _shared.edition,
        imageUrl: _shared.imageUrl,
        imageHash: _shared.imageHash,
        minifiedImageUrl: _shared.minifiedImageUrl,
        minifiedImageHash: _shared.minifiedImageHash,
        mass: _shared.mass,
        legality: WboLegality.parse(_shared.legalityRaw),
        isIncomplete: _shared.isIncomplete,
      );
}

/// Shared parsing for OverBlade/MetalBlade/MainBlade/AssistBlade — same
/// columns (type, spinDir, attack, defense, stamina) beyond the fields
/// _SharedPartFieldsModel already covers.
class _TypedStatPartModel {
  _TypedStatPartModel(Map<String, dynamic> row)
      : shared = _SharedPartFieldsModel(row),
        typeRaw = requiredString(row, 'type'),
        spinDirectionRaw = requiredString(row, 'spinDir'),
        attack = parseDouble(ciGet(row, 'attack')),
        defense = parseDouble(ciGet(row, 'defense')),
        stamina = parseDouble(ciGet(row, 'stamina'));

  final _SharedPartFieldsModel shared;
  final String typeRaw, spinDirectionRaw;
  final double? attack, defense, stamina;

  StatBlock get stats => StatBlock({
        StatKey.attack: StatSpread.parse(attack),
        StatKey.defense: StatSpread.parse(defense),
        StatKey.stamina: StatSpread.parse(stamina),
      });
}

// ── OVER BLADE MODEL ────────────────────────────────────────────
class OverBladeModel {
  OverBladeModel.fromSheetJson(Map<String, dynamic> row)
      : _p = _TypedStatPartModel(row);
  final _TypedStatPartModel _p;

  OverBlade toEntity() => OverBlade(
        dataId: _p.shared.dataId,
        parentPartId: _p.shared.parentPartId,
        variantLabel: _p.shared.variantLabel,
        manufacturer: _p.shared.manufacturer,
        hobbyName: _p.shared.hobbyName,
        hobbyGeneration: _p.shared.hobbyGeneration,
        code: _p.shared.code,
        name: _p.shared.name,
        edition: _p.shared.edition,
        imageUrl: _p.shared.imageUrl,
        imageHash: _p.shared.imageHash,
        minifiedImageUrl: _p.shared.minifiedImageUrl,
        minifiedImageHash: _p.shared.minifiedImageHash,
        mass: _p.shared.mass,
        legality: WboLegality.parse(_p.shared.legalityRaw),
        isIncomplete: _p.shared.isIncomplete,
        type: BeybladeArchetype.parse(_p.typeRaw),
        spinDirection: SpinDirection.parse(_p.spinDirectionRaw),
        stats: _p.stats,
      );
}

// ── METAL BLADE MODEL ───────────────────────────────────────────
class MetalBladeModel {
  MetalBladeModel.fromSheetJson(Map<String, dynamic> row)
      : _p = _TypedStatPartModel(row);
  final _TypedStatPartModel _p;

  MetalBlade toEntity() => MetalBlade(
        dataId: _p.shared.dataId,
        parentPartId: _p.shared.parentPartId,
        variantLabel: _p.shared.variantLabel,
        manufacturer: _p.shared.manufacturer,
        hobbyName: _p.shared.hobbyName,
        hobbyGeneration: _p.shared.hobbyGeneration,
        code: _p.shared.code,
        name: _p.shared.name,
        edition: _p.shared.edition,
        imageUrl: _p.shared.imageUrl,
        imageHash: _p.shared.imageHash,
        minifiedImageUrl: _p.shared.minifiedImageUrl,
        minifiedImageHash: _p.shared.minifiedImageHash,
        mass: _p.shared.mass,
        legality: WboLegality.parse(_p.shared.legalityRaw),
        isIncomplete: _p.shared.isIncomplete,
        type: BeybladeArchetype.parse(_p.typeRaw),
        spinDirection: SpinDirection.parse(_p.spinDirectionRaw),
        stats: _p.stats,
      );
}

// ── MAIN BLADE MODEL ────────────────────────────────────────────
class MainBladeModel {
  MainBladeModel.fromSheetJson(Map<String, dynamic> row)
      : _p = _TypedStatPartModel(row);
  final _TypedStatPartModel _p;

  MainBlade toEntity() => MainBlade(
        dataId: _p.shared.dataId,
        parentPartId: _p.shared.parentPartId,
        variantLabel: _p.shared.variantLabel,
        manufacturer: _p.shared.manufacturer,
        hobbyName: _p.shared.hobbyName,
        hobbyGeneration: _p.shared.hobbyGeneration,
        code: _p.shared.code,
        name: _p.shared.name,
        edition: _p.shared.edition,
        imageUrl: _p.shared.imageUrl,
        imageHash: _p.shared.imageHash,
        minifiedImageUrl: _p.shared.minifiedImageUrl,
        minifiedImageHash: _p.shared.minifiedImageHash,
        mass: _p.shared.mass,
        legality: WboLegality.parse(_p.shared.legalityRaw),
        isIncomplete: _p.shared.isIncomplete,
        type: BeybladeArchetype.parse(_p.typeRaw),
        spinDirection: SpinDirection.parse(_p.spinDirectionRaw),
        stats: _p.stats,
      );
}

// ── ASSIST BLADE MODEL ──────────────────────────────────────────
class AssistBladeModel {
  AssistBladeModel.fromSheetJson(Map<String, dynamic> row)
      : _p = _TypedStatPartModel(row),
        requiresSimpleRatchet = parseBool(ciGet(row, 'requiresSimpleRatchet'));
  final _TypedStatPartModel _p;
  final bool requiresSimpleRatchet;

  AssistBlade toEntity() => AssistBlade(
        dataId: _p.shared.dataId,
        parentPartId: _p.shared.parentPartId,
        variantLabel: _p.shared.variantLabel,
        manufacturer: _p.shared.manufacturer,
        hobbyName: _p.shared.hobbyName,
        hobbyGeneration: _p.shared.hobbyGeneration,
        code: _p.shared.code,
        name: _p.shared.name,
        edition: _p.shared.edition,
        imageUrl: _p.shared.imageUrl,
        imageHash: _p.shared.imageHash,
        minifiedImageUrl: _p.shared.minifiedImageUrl,
        minifiedImageHash: _p.shared.minifiedImageHash,
        mass: _p.shared.mass,
        legality: WboLegality.parse(_p.shared.legalityRaw),
        isIncomplete: _p.shared.isIncomplete,
        type: BeybladeArchetype.parse(_p.typeRaw),
        spinDirection: SpinDirection.parse(_p.spinDirectionRaw),
        stats: _p.stats,
        requiresSimpleRatchet: requiresSimpleRatchet,
      );
}

// ── PRODUCT MODEL ───────────────────────────────────────────────
class ProductModel {
  ProductModel.fromSheetJson(Map<String, dynamic> row)
      : productId = requiredString(row, 'productID'),
        manufacturer = requiredString(row, 'manufacturer'),
        hobbyName = requiredString(row, 'hobbyName'),
        hobbyGeneration = requiredString(row, 'hobbyGeneration'),
        productName = requiredString(row, 'productName'),
        productType = nullableString(ciGet(row, 'productType')),
        releaseDateRaw = nullableString(ciGet(row, 'releaseDate')),
        itemCost = parseDouble(ciGet(row, 'itemCost')),
        boxImageUrl = nullableString(ciGet(row, 'imageUrl')),
        boxImageHash = nullableString(ciGet(row, 'imageHash')),
        minifiedBoxImageUrl = nullableString(ciGet(row, 'minifiedImageUrl')),
        minifiedBoxImageHash = nullableString(ciGet(row, 'minifiedImageHash')),
        sku = nullableString(ciGet(row, 'sku')),
        description = nullableString(ciGet(row, 'description')),
        isIncomplete = parseBool(ciGet(row, 'incompleteData'));

  final String productId, manufacturer, hobbyName, hobbyGeneration, productName;
  final String? productType,
      releaseDateRaw,
      boxImageUrl,
      boxImageHash,
      minifiedBoxImageUrl,
      minifiedBoxImageHash,
      sku,
      description;
  final double? itemCost;
  final bool isIncomplete;

  Product toEntity() => Product(
        productId: productId,
        manufacturer: manufacturer,
        hobbyName: hobbyName,
        hobbyGeneration: hobbyGeneration,
        productName: productName,
        productType: productType,
        releaseDate:
            releaseDateRaw == null ? null : DateTime.tryParse(releaseDateRaw!),
        itemCost: itemCost,
        boxImageUrl: boxImageUrl,
        boxImageHash: boxImageHash,
        minifiedBoxImageUrl: minifiedBoxImageUrl,
        minifiedBoxImageHash: minifiedBoxImageHash,
        sku: sku,
        description: description,
        isIncomplete: isIncomplete,
      );
}

// ── PRODUCT CONTENT MODEL ───────────────────────────────────────
/// Plain pass-through -- ProductContents has no image, no
/// incompleteData formula, just the four link columns.
class ProductContentModel {
  ProductContentModel.fromSheetJson(Map<String, dynamic> row)
      : productId = requiredString(row, 'productID'),
        partType = requiredString(row, 'partType'),
        partDataId = requiredString(row, 'partDataID'),
        quantity = parseInt(ciGet(row, 'quantity')) ?? 1;

  final String productId, partType, partDataId;
  final int quantity;

  ProductContent toEntity() => ProductContent(
        productId: productId,
        partType: partType,
        partDataId: partDataId,
        quantity: quantity,
      );
}

// ── ACCESSORY MODEL ─────────────────────────────────────────────
class AccessoryModel {
  AccessoryModel.fromSheetJson(Map<String, dynamic> row)
      : dataId = requiredString(row, 'dataID'),
        accessoryTypeRaw = requiredString(row, 'accessoryType'),
        subType = nullableString(ciGet(row, 'subType')),
        manufacturer = requiredString(row, 'manufacturer'),
        hobbyName = requiredString(row, 'hobbyName'),
        hobbyGeneration = requiredString(row, 'hobbyGeneration'),
        name = requiredString(row, 'name'),
        itemCost = parseDouble(ciGet(row, 'itemCost')),
        imageUrl = nullableString(ciGet(row, 'imageUrl')),
        imageHash = nullableString(ciGet(row, 'imageHash')),
        minifiedImageUrl = nullableString(ciGet(row, 'minifiedImageUrl')),
        minifiedImageHash = nullableString(ciGet(row, 'minifiedImageHash')),
        description = nullableString(ciGet(row, 'description')),
        isIncomplete = parseBool(ciGet(row, 'incompleteData'));

  final String dataId,
      accessoryTypeRaw,
      manufacturer,
      hobbyName,
      hobbyGeneration,
      name;
  final String? subType,
      imageUrl,
      imageHash,
      minifiedImageUrl,
      minifiedImageHash,
      description;
  final double? itemCost;
  final bool isIncomplete;

  Accessory toEntity() => Accessory(
        dataId: dataId,
        accessoryType: AccessoryType.parse(accessoryTypeRaw),
        subType: subType,
        manufacturer: manufacturer,
        hobbyName: hobbyName,
        hobbyGeneration: hobbyGeneration,
        name: name,
        itemCost: itemCost,
        imageUrl: imageUrl,
        imageHash: imageHash,
        minifiedImageUrl: minifiedImageUrl,
        minifiedImageHash: minifiedImageHash,
        description: description,
        isIncomplete: isIncomplete,
      );
}

class SyncMetadataModel {
  SyncMetadataModel({
    this.lastMetadataSyncAtMillis,
    this.catalogVersion,
    this.catalogSha256,
  });

  factory SyncMetadataModel.initial() => SyncMetadataModel();

  final int? lastMetadataSyncAtMillis;
  final String? catalogVersion;
  final String? catalogSha256;

  factory SyncMetadataModel.fromJson(Map<String, dynamic> json) =>
      SyncMetadataModel(
        lastMetadataSyncAtMillis:
            (json['lastMetadataSyncAtMillis'] as num?)?.toInt(),
        catalogVersion: json['catalogVersion'] as String?,
        catalogSha256: json['catalogSha256'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'lastMetadataSyncAtMillis': lastMetadataSyncAtMillis,
        'catalogVersion': catalogVersion,
        'catalogSha256': catalogSha256,
      };

  SyncMetadataModel copyWith({
    int? lastMetadataSyncAtMillis,
    String? catalogVersion,
    String? catalogSha256,
  }) =>
      SyncMetadataModel(
        lastMetadataSyncAtMillis:
            lastMetadataSyncAtMillis ?? this.lastMetadataSyncAtMillis,
        catalogVersion: catalogVersion ?? this.catalogVersion,
        catalogSha256: catalogSha256 ?? this.catalogSha256,
      );

  SyncMetadata toEntity() => SyncMetadata(
        lastMetadataSyncAt: lastMetadataSyncAtMillis == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(lastMetadataSyncAtMillis!),
        catalogVersion: catalogVersion,
        catalogSha256: catalogSha256,
      );
}

class ComboModel {
  ComboModel(
      {required this.id,
      required this.name,
      required this.loadout,
      required this.createdAtMillis});

  ComboModel.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        loadout = BeybladeLoadout.fromJson(
            Map<String, dynamic>.from(json['loadout'] as Map)),
        createdAtMillis = (json['createdAtMillis'] as num).toInt();

  final String id;
  final String name;
  final BeybladeLoadout loadout;
  final int createdAtMillis;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'loadout': loadout.toJson(),
        'createdAtMillis': createdAtMillis
      };

  Combo toEntity() => Combo(
      id: id,
      name: name,
      loadout: loadout,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis));
}

class DeckModel {
  DeckModel(
      {required this.id,
      required this.name,
      required this.comboIds,
      required this.createdAtMillis});

  DeckModel.fromJson(Map<String, dynamic> json)
      : id = json['id'] as String,
        name = json['name'] as String,
        comboIds = List<String>.from(json['comboIds'] as List),
        createdAtMillis = (json['createdAtMillis'] as num).toInt();

  final String id;
  final String name;
  final List<String> comboIds;
  final int createdAtMillis;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'comboIds': comboIds,
        'createdAtMillis': createdAtMillis
      };

  Deck toEntity() => Deck(
      id: id,
      name: name,
      comboIds: comboIds,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis));
}
