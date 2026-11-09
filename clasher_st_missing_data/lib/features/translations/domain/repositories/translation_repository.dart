import '../../../../core/error/failure.dart';
import '../entities/translation_models.dart';
import '../entities/translation_project.dart';

/// Strings of an app and their translation sheet. The project is only read; the sheet is written on save; generated
/// files go to the export folder. Implemented by the Python engine (translation_tool.py).
abstract class TranslationRepository {
  Future<Result<TrSummary>> open(TranslationProject project);
  Future<Result<TrSummary>> summary();

  /// Re-reads the project (constants, hard-coded strings, usage) -> hard-coded strings found.
  Future<Result<int>> scan();
  Future<Result<TrReport>> report();
  Future<Result<TrKeysPage>> keys({
    String query = '',
    String? status,
    String? missingIn,
    int limit = 5000,
  });
  Future<Result<List<HardcodedString>>> hardcoded();

  /// [{key, column, text}] -> the problems the new texts have.
  Future<Result<List<TrProblem>>> setCells(
    List<({String key, String column, String text})> items,
  );

  /// -> (added, skipped with reasons)
  Future<Result<({List<String> added, List<String> skipped})>> addRows(
    List<({String key, String english, Map<String, String> meta})> items,
  );
  Future<Result<void>> addLanguage({
    required String column,
    String? code,
    String? name,
    String? country,
  });
  Future<Result<void>> setLanguages(List<TrLanguage> languages);
  Future<Result<String?>> undo();

  /// -> backup file. [force] overwrites a file that changed on disk since it was opened.
  Future<Result<String>> save({bool force = false});
  Future<Result<int>> recoverUnsaved();
  Future<Result<void>> discardUnsaved();

  Future<Result<ExportResult>> exportDart(
    String outDir, {
    List<String> addKeys = const [],
    List<String> updateEnglish = const [],
    Map<String, String> sections = const {},
  });

  /// Copies the exported constants files into the project (backups first) -> files written.
  Future<Result<List<String>>> applyExport(String outDir);
  Future<Result<PackReport>> buildPacks(String outDir, {bool strict = false});
}
