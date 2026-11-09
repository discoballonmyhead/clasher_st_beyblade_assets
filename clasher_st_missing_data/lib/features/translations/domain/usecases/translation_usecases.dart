import '../../../../core/error/failure.dart';
import '../entities/translation_models.dart';
import '../entities/translation_project.dart';
import '../repositories/translation_repository.dart';

class OpenTranslationProject {
  const OpenTranslationProject(this._repo);
  final TranslationRepository _repo;

  /// Opens, then scans the project, so the report is complete.
  Future<Result<TrSummary>> call(TranslationProject p) async {
    final s = await _repo.open(p);
    if (s case Ok()) await _repo.scan();
    return s;
  }
}

class RefreshTranslations {
  const RefreshTranslations(this._repo);
  final TranslationRepository _repo;

  /// Re-scans the project and returns the summary and the report.
  Future<Result<(TrSummary, TrReport)>> call({bool rescan = true}) async {
    if (rescan) {
      final s = await _repo.scan();
      if (s case Err(:final failure)) return Err(failure);
    }
    final sum = await _repo.summary();
    final rep = await _repo.report();
    return switch ((sum, rep)) {
      (Ok(value: final a), Ok(value: final b)) => Ok((a, b)),
      (Err(:final failure), _) => Err(failure),
      (_, Err(:final failure)) => Err(failure),
    };
  }
}

class EditTranslations {
  const EditTranslations(this._repo);
  final TranslationRepository _repo;
  Future<Result<List<TrProblem>>> call(
    List<({String key, String column, String text})> items,
  ) => _repo.setCells(items);
}

class AddTranslationKeys {
  const AddTranslationKeys(this._repo);
  final TranslationRepository _repo;
  Future<Result<({List<String> added, List<String> skipped})>> call(
    List<({String key, String english, Map<String, String> meta})> items,
  ) => _repo.addRows(items);
}

class ExportAppConstants {
  const ExportAppConstants(this._repo);
  final TranslationRepository _repo;
  Future<Result<ExportResult>> call(
    String outDir, {
    List<String> addKeys = const [],
    List<String> updateEnglish = const [],
    Map<String, String> sections = const {},
  }) => _repo.exportDart(
    outDir,
    addKeys: addKeys,
    updateEnglish: updateEnglish,
    sections: sections,
  );
}

class BuildLanguagePacks {
  const BuildLanguagePacks(this._repo);
  final TranslationRepository _repo;
  Future<Result<PackReport>> call(String outDir, {bool strict = false}) =>
      _repo.buildPacks(outDir, strict: strict);
}
