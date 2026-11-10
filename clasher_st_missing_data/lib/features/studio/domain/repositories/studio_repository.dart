import '../../../../core/error/failure.dart';
import '../entities/studio_models.dart';

/// The workspace, packaging profiles, publishing and scrapers. Long steps are jobs: start one, follow
/// [jobEvents] for its id, stop it with [stopJob]. Implemented by studio_tool.py.
abstract class StudioRepository {
  Future<Result<StudioWorkspace>> workspace();
  Future<Result<StudioWorkspace>> saveWorkspace(List<Hobby> hobbies);

  Future<Result<List<SheetProfile>>> profiles();
  Future<Result<SheetProfile>> saveProfile(String sheet, List<ColumnRule> columns);

  Future<Result<ToolsStatus>> tools();
  Future<Result<GitStatus>> gitStatus(String repo, {List<String> paths = const ['data']});

  /// Sets user.name / user.email in [repo] only (not globally) -> the new status.
  Future<Result<GitStatus>> setGitIdentity(String repo, {required String name, required String email});
  Future<Result<List<ReleaseInfo>>> releases(String slug);
  Future<Result<List<ReleaseAsset>>> releaseAssets(String slug, String tag);

  // jobs -> their id
  Future<Result<String>> package({
    required List<String> books,
    required String out,
    required String owner,
    required String repo,
    required String branch,
  });
  Future<Result<String>> commitPush({
    required String repo,
    required String message,
    List<String> paths = const ['data'],
    bool push = true,
  });
  Future<Result<String>> buildRelease({
    required String data,
    required String out,
    required String tag,
    required String owner,
    required String repo,
    bool dropInvalid = false,
    String? appAssets,
  });
  Future<Result<String>> publishRelease({
    required String slug,
    required String tag,
    required List<String> files,
    String? title,
    String? notes,
    bool latest = false,
  });
  Future<Result<String>> scrape({required List<String> targets, Map<String, Object?> options = const {}});
  Future<Result<void>> stopJob(String id);
  Stream<JobEvent> get jobEvents;

  // scrapers
  Future<Result<ScraperOverview>> scraperTargets();
  Future<Result<Map<String, dynamic>>> scraperTargetConfig(String target);
  Future<Result<void>> saveScraperTargetConfig(String target, Map<String, dynamic> config);
  Future<Result<void>> saveScraperSettings({String? userAgent, Map<String, Object?>? politeness});

  /// The plugin file for a hobby + generation: (path, text, exists) - the text is a template when it doesn't exist.
  Future<Result<({String path, String text, bool exists, String scraperPath})>> codeFiles(String hobby, String generation);
  Future<Result<({String path, String text})>> readCode(String path);
  Future<Result<CodeCheck>> checkCode(String path, String text);
  Future<Result<void>> saveCode(String path, String text);
}
