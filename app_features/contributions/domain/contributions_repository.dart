import 'package:clasher_st/features/contributions/domain/entities.dart';

/// Sends a picture with who sent it. Throws [ContributionException] with a message to show.
abstract class ContributionsRepository {
  /// False when the app wasn't built with an endpoint: the page then says the feature isn't set up.
  bool get isConfigured;

  Future<ContributionReceipt> submit(ContributionDraft draft, Contributor contributor);
}

/// Who is signed in (their username). The default reads the Supabase session; register another one in DI
/// if usernames live elsewhere (a profiles table ...).
abstract class ContributorIdentity {
  /// Null when nobody is signed in or there's no username to send.
  Future<Contributor?> current();
}

/// Lets the person pick what the picture is of from the catalog.
abstract class ContributionTargetSearch {
  /// [type]: "parts" (every part type), "bladers", "products" or "accessories".
  Future<List<ContributionTarget>> search(String type, String query, {int limit = 30});
}

/// The published list of what's missing (data/_wanted.json on the CDN).
abstract class WantedSource {
  bool get isConfigured;

  /// [refresh] skips the in-memory copy.
  Future<WantedList> load({bool refresh = false});
}

/// The phone's gallery / camera.
abstract class ContributionPicturePicker {
  Future<PickedPicture?> pick({bool camera = false});
}
