import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';

/// Checks a draft the way the server will, so the person hears about a problem before uploading.
class SubmitContributionUseCase {
  const SubmitContributionUseCase(this._repo, this._identity);

  final ContributionsRepository _repo;
  final ContributorIdentity _identity;

  static const maxBytes = 6 * 1024 * 1024;

  bool get isConfigured => _repo.isConfigured;

  Future<Contributor?> contributor() => _identity.current();

  Future<ContributionReceipt> call(ContributionDraft d) async {
    if (!_repo.isConfigured) {
      throw const ContributionException('not_configured', 'Sending pictures isn\'t set up in this version.');
    }
    final who = await _identity.current();
    if (who == null || who.username.trim().isEmpty) {
      throw const ContributionException('signed_out', 'Sign in to send pictures.');
    }
    if (!d.consent) {
      throw const ContributionException('invalid', 'Confirm you may share this picture.');
    }
    if (d.target.isOther && (d.note ?? '').trim().isEmpty) {
      throw const ContributionException('invalid', 'Say what the picture is of.');
    }
    if (!d.target.isOther && d.target.id.isEmpty) {
      throw const ContributionException('invalid', 'Pick what the picture is of.');
    }
    if (d.kind == ContributionKind.fullBodyImage && !d.target.isBlader) {
      throw const ContributionException('invalid', 'Full-body pictures are for bladers.');
    }
    if (d.picture.bytes.length > maxBytes) {
      throw const ContributionException('too_large', 'The picture is too big (max 6 MB).');
    }
    if (sniffImageMime(d.picture.bytes) == null) {
      throw const ContributionException('invalid', 'Pick a JPEG, PNG or WebP picture.');
    }
    return _repo.submit(d, who);
  }
}
