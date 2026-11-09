import '../../../../core/bridge/engine_bridge.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/translation_models.dart';
import '../../domain/entities/translation_project.dart';
import '../../domain/repositories/translation_repository.dart';
import '../datasources/translation_data_source.dart';
import '../models/translation_mappers.dart';

class TranslationRepositoryImpl implements TranslationRepository {
  TranslationRepositoryImpl(this._ds);

  final TranslationDataSource _ds;

  Future<Result<T>> _guard<T>(Future<T> Function() run) async {
    try {
      return Ok(await run());
    } on EngineException catch (e) {
      return Err(Failure(e.message));
    } on TypeError catch (e) {
      return Err(Failure('Unexpected answer from the translation engine: $e'));
    }
  }

  @override
  Future<Result<TrSummary>> open(TranslationProject p) => _guard(
    () async =>
        summaryFromJson(await _ds.open(p.projectDir, p.sheetPath, p.overrides)),
  );

  @override
  Future<Result<TrSummary>> summary() =>
      _guard(() async => summaryFromJson(await _ds.summary()));

  @override
  Future<Result<int>> scan() => _guard(
    () async => ((await _ds.scan())['hardcoded'] as num? ?? 0).toInt(),
  );

  @override
  Future<Result<TrReport>> report() =>
      _guard(() async => reportFromJson(await _ds.report()));

  @override
  Future<Result<TrKeysPage>> keys({
    String query = '',
    String? status,
    String? missingIn,
    int limit = 5000,
  }) => _guard(
    () async =>
        keysPageFromJson(await _ds.keys(query, status, missingIn, limit)),
  );

  @override
  Future<Result<List<HardcodedString>>> hardcoded() => _guard(
    () async => [
      for (final h in await _ds.hardcoded())
        hardcodedFromJson(Map<String, dynamic>.from(h as Map)),
    ],
  );

  @override
  Future<Result<List<TrProblem>>> setCells(
    List<({String key, String column, String text})> items,
  ) => _guard(() async {
    final r = await _ds.set([
      for (final i in items) {'key': i.key, 'column': i.column, 'text': i.text},
    ]);
    return [
      for (final p in (r['problems'] as List? ?? const []))
        problemFromJson(Map<String, dynamic>.from(p as Map)),
    ];
  });

  @override
  Future<Result<({List<String> added, List<String> skipped})>> addRows(
    List<({String key, String english, Map<String, String> meta})> items,
  ) => _guard(() async {
    final r = await _ds.addRows([
      for (final i in items)
        {'key': i.key, 'english': i.english, 'meta': i.meta},
    ]);
    return (
      added: [for (final k in (r['added'] as List? ?? const [])) '$k'],
      skipped: [
        for (final s in (r['skipped'] as List? ?? const []))
          '${(s as Map)['reason']}',
      ],
    );
  });

  @override
  Future<Result<void>> addLanguage({
    required String column,
    String? code,
    String? name,
    String? country,
  }) => _guard(
    () => _ds.addLanguage({
      'column': column,
      'code': code,
      'name': name,
      'country': country,
    }),
  );

  @override
  Future<Result<void>> setLanguages(List<TrLanguage> languages) =>
      _guard(() => _ds.setLanguages([for (final l in languages) l.toRow()]));

  @override
  Future<Result<String?>> undo() =>
      _guard(() async => (await _ds.undo())['undone'] as String?);

  @override
  Future<Result<String>> save({bool force = false}) =>
      _guard(() async => '${(await _ds.save(force))['backup']}');

  @override
  Future<Result<int>> recoverUnsaved() => _guard(
    () async => ((await _ds.recover())['recovered'] as num? ?? 0).toInt(),
  );

  @override
  Future<Result<void>> discardUnsaved() => _guard(() => _ds.discardUnsaved());

  @override
  Future<Result<ExportResult>> exportDart(
    String outDir, {
    List<String> addKeys = const [],
    List<String> updateEnglish = const [],
    Map<String, String> sections = const {},
  }) => _guard(
    () async => exportFromJson(
      await _ds.exportDart(outDir, addKeys, updateEnglish, sections),
    ),
  );

  @override
  Future<Result<List<String>>> applyExport(String outDir) => _guard(
    () async => [
      for (final f
          in ((await _ds.applyExport(outDir))['written'] as List? ?? const []))
        '$f',
    ],
  );

  @override
  Future<Result<PackReport>> buildPacks(String outDir, {bool strict = false}) =>
      _guard(
        () async => packsFromJson(await _ds.buildPacks(outDir, strict), outDir),
      );
}
