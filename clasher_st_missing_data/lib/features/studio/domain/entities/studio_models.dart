import 'package:equatable/equatable.dart';

/// A workbook of a hobby (parts, products, tcg, cards ...).
class WorkbookRef extends Equatable {
  const WorkbookRef({required this.role, required this.file, required this.path, this.exists = false});
  final String role;
  final String file;
  final String path;
  final bool exists;

  Map<String, Object> toJson() => {'role': role, 'file': file};

  @override
  List<Object?> get props => [role, file, path, exists];
}

/// A hobby (Beyblade, Beyblade TCG, Yu-Gi-Oh! ...) with its generations (series, or years for cards).
class Hobby extends Equatable {
  const Hobby({
    required this.name,
    required this.generations,
    this.kind = 'parts',
    this.workbooks = const [],
    this.packaged = false,
    this.scraped = false,
  });

  final String name;
  final List<String> generations;

  /// parts (spinning tops) or cards.
  final String kind;
  final List<WorkbookRef> workbooks;

  /// The packager / the scraper know this hobby (Beyblade, Beyblade TCG today).
  final bool packaged;
  final bool scraped;

  Hobby copyWith({String? name, List<String>? generations, String? kind, List<WorkbookRef>? workbooks}) => Hobby(
    name: name ?? this.name,
    generations: generations ?? this.generations,
    kind: kind ?? this.kind,
    workbooks: workbooks ?? this.workbooks,
    packaged: packaged,
    scraped: scraped,
  );

  Map<String, Object> toJson() => {
    'name': name,
    'kind': kind,
    'generations': generations,
    'workbooks': [for (final w in workbooks) w.toJson()],
    'packaged': packaged,
    'scraped': scraped,
  };

  @override
  List<Object?> get props => [name, generations, kind, workbooks, packaged, scraped];
}

class StudioWorkspace extends Equatable {
  const StudioWorkspace({required this.root, required this.hobbies});
  final String root;
  final List<Hobby> hobbies;

  Hobby? hobby(String? name) => hobbies.where((h) => h.name == name).firstOrNull;

  /// The hobby a workbook belongs to (by path or file name).
  Hobby? hobbyOfWorkbook(String path) {
    final norm = path.replaceAll('\\', '/');
    for (final h in hobbies) {
      for (final w in h.workbooks) {
        if (w.path.replaceAll('\\', '/') == norm || norm.endsWith('/${w.file}')) return h;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [root, hobbies];
}

class ToolsStatus extends Equatable {
  const ToolsStatus({this.git = false, this.gh = false, this.ghUser, this.ghSignedIn = false, this.ghDetail = ''});
  final bool git;
  final bool gh;
  final String? ghUser;
  final bool ghSignedIn;
  final String ghDetail;

  /// Can create releases.
  bool get canPublish => gh && ghSignedIn;

  @override
  List<Object?> get props => [git, gh, ghUser, ghSignedIn, ghDetail];
}

class GitStatus extends Equatable {
  const GitStatus({
    this.isRepo = false,
    this.branch = '',
    this.remote = '',
    this.changed = 0,
    this.changedImages = 0,
    this.sample = const [],
    this.ahead,
    this.behind,
    this.detail = '',
  });

  final bool isRepo;
  final String branch;
  final String remote;
  final int changed;
  final int changedImages;
  final List<String> sample;
  final int? ahead;
  final int? behind;
  final String detail;

  @override
  List<Object?> get props => [isRepo, branch, remote, changed, changedImages, sample, ahead, behind, detail];
}

/// One problem from the catalog check (what the app would reject).
class CheckItem extends Equatable {
  const CheckItem({required this.sheet, required this.message, this.id});
  final String sheet;
  final String? id;
  final String message;
  @override
  List<Object?> get props => [sheet, id, message];
}

class PackageResult extends Equatable {
  const PackageResult({
    required this.out,
    required this.ok,
    this.errors = const [],
    this.warnings = const [],
    this.errorCount = 0,
    this.warningCount = 0,
    this.rowsPerSheet = const {},
    this.changes = const {},
  });

  final String out;

  /// The catalog check passed: a release can be built without --drop-invalid.
  final bool ok;
  final List<CheckItem> errors;
  final List<CheckItem> warnings;
  final int errorCount;
  final int warningCount;
  final Map<String, int> rowsPerSheet;

  /// What changed since the last package (manifest "changes").
  final Map<String, dynamic> changes;

  @override
  List<Object?> get props => [out, ok, errors, warnings, errorCount, warningCount, rowsPerSheet, changes];
}

class ReleaseBuild extends Equatable {
  const ReleaseBuild({required this.folder, required this.manifest, required this.files, this.packs = const []});
  final String folder;

  /// catalog_manifest.json: what the Supabase manifest function returns.
  final Map<String, dynamic> manifest;
  final List<String> files;
  final List<Map<String, dynamic>> packs;

  String get tag => '${manifest['releaseTag'] ?? ''}';

  @override
  List<Object?> get props => [folder, manifest, files, packs];
}

class PublishResult extends Equatable {
  const PublishResult({required this.created, this.url, this.assets = const []});
  final bool created;
  final String? url;
  final List<String> assets;
  @override
  List<Object?> get props => [created, url, assets];
}

class ReleaseInfo extends Equatable {
  const ReleaseInfo({required this.tag, this.name = '', this.publishedAt, this.isLatest = false, this.isDraft = false});
  final String tag;
  final String name;
  final DateTime? publishedAt;
  final bool isLatest;
  final bool isDraft;
  @override
  List<Object?> get props => [tag, name, publishedAt, isLatest, isDraft];
}

class ReleaseAsset extends Equatable {
  const ReleaseAsset({required this.name, this.size = 0, this.downloads = 0});
  final String name;
  final int size;
  final int downloads;
  @override
  List<Object?> get props => [name, size, downloads];
}

enum Criticality { required, recommended, optional }

class ColumnRule extends Equatable {
  const ColumnRule({
    required this.name,
    this.include = true,
    this.criticality = Criticality.recommended,
    this.defaultCriticality = Criticality.recommended,
    this.locked = false,
    this.appRequired = false,
  });

  final String name;

  /// Goes into the JSON.
  final bool include;
  final Criticality criticality;
  final Criticality defaultCriticality;

  /// Ids, images and fields the app reads as required: always included, always required.
  final bool locked;
  final bool appRequired;

  bool get changed => !locked && (!include || criticality != defaultCriticality);

  ColumnRule copyWith({bool? include, Criticality? criticality}) => ColumnRule(
    name: name,
    include: include ?? this.include,
    criticality: criticality ?? this.criticality,
    defaultCriticality: defaultCriticality,
    locked: locked,
    appRequired: appRequired,
  );

  @override
  List<Object?> get props => [name, include, criticality, defaultCriticality, locked, appRequired];
}

/// What one JSON sheet (blades.json, products.json ...) carries.
class SheetProfile extends Equatable {
  const SheetProfile({
    required this.sheet,
    required this.tab,
    required this.workbook,
    this.generation,
    this.source = 'schema',
    this.columns = const [],
  });

  final String sheet;
  final String tab;
  final String workbook;
  final String? generation;

  /// workbook (read from the tab's header row) or schema (the tab isn't in the workbook yet).
  final String source;
  final List<ColumnRule> columns;

  SheetProfile withColumns(List<ColumnRule> c) =>
      SheetProfile(sheet: sheet, tab: tab, workbook: workbook, generation: generation, source: source, columns: c);

  @override
  List<Object?> get props => [sheet, tab, workbook, generation, source, columns];
}

class ScraperTarget extends Equatable {
  const ScraperTarget({
    required this.target,
    required this.kind,
    required this.generation,
    required this.hobby,
    this.key,
    this.categories = const [],
    this.progress,
    this.hasPlugin = false,
  });

  /// e.g. parts:X:blades, products:Burst, tcg:Original:cards
  final String target;
  final String kind;
  final String generation;
  final String hobby;
  final String? key;
  final List<String> categories;
  final Map<String, dynamic>? progress;
  final bool hasPlugin;

  String get label => key == null ? kind : '$kind / $key';

  @override
  List<Object?> get props => [target, kind, generation, hobby, key, categories, progress, hasPlugin];
}

class ScraperOverview extends Equatable {
  const ScraperOverview({
    required this.targets,
    this.configPath = '',
    this.userAgent = '',
    this.politeness = const {},
    this.stateDir = '',
  });
  final List<ScraperTarget> targets;
  final String configPath;
  final String userAgent;
  final Map<String, dynamic> politeness;
  final String stateDir;

  bool get userAgentNeedsContact => userAgent.contains('CHANGE_ME');

  @override
  List<Object?> get props => [targets, configPath, userAgent, politeness, stateDir];
}

class CodeCheck extends Equatable {
  const CodeCheck({required this.ok, this.line, this.message = ''});
  final bool ok;
  final int? line;
  final String message;
  @override
  List<Object?> get props => [ok, line, message];
}

/// Output of a background job: a line, or the end.
class JobEvent extends Equatable {
  const JobEvent({required this.id, this.line, this.done = false, this.ok = false, this.result, this.error});
  final String id;
  final String? line;
  final bool done;
  final bool ok;
  final Object? result;
  final String? error;
  @override
  List<Object?> get props => [id, line, done, ok, result, error];
}
