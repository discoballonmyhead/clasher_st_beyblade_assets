import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The username of the signed-in Supabase user: the first of [metadataKeys] set in the user's metadata, else
/// the part of the email before the @. Null when nobody is signed in.
///
/// If usernames live in a profiles table, register your own [ContributorIdentity] instead (or pass
/// [lookup]).
class SupabaseContributorIdentity implements ContributorIdentity {
  SupabaseContributorIdentity(this._client, {this.lookup});

  final SupabaseClient _client;

  /// Optional: fetch the username yourself (e.g. from a profiles table) for a user id.
  final Future<String?> Function(String userId)? lookup;

  static const metadataKeys = ['username', 'user_name', 'preferred_username', 'display_name', 'full_name', 'name'];

  @override
  Future<Contributor?> current() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    String? name;
    if (lookup != null) {
      try {
        name = await lookup!(user.id);
      } catch (_) {}
    }
    final meta = user.userMetadata ?? const {};
    for (final k in metadataKeys) {
      if (name != null && name.trim().isNotEmpty) break;
      final v = meta[k];
      if (v is String && v.trim().isNotEmpty) name = v.trim();
    }
    if ((name == null || name.isEmpty) && (user.email ?? '').contains('@')) {
      name = user.email!.split('@').first;
    }
    if (name == null || name.isEmpty) return null;
    return Contributor(username: name, userId: user.id);
  }
}
