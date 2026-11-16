import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:equatable/equatable.dart';

class PartPickerState extends Equatable {
  const PartPickerState({
    this.loading = true,
    this.all = const [],
    this.query = '',
    this.results = const [],
    this.generation,
    this.manufacturer,
    this.generations = const [],
    this.manufacturers = const [],
    this.error,
  });

  final bool loading;
  final List<BeybladePart> all;
  final String query;
  final List<BeybladePart> results;

  /// Active filters; null means "all".
  final String? generation;
  final String? manufacturer;

  /// What the loaded parts contain, for the filter chips. A chip row is
  /// only shown when there is more than one value to choose between.
  final List<String> generations;
  final List<String> manufacturers;

  /// Set when loading failed; the picker shows it with a retry.
  final String? error;

  PartPickerState copyWith({
    bool? loading,
    List<BeybladePart>? all,
    String? query,
    List<BeybladePart>? results,
    String? generation,
    bool clearGeneration = false,
    String? manufacturer,
    bool clearManufacturer = false,
    List<String>? generations,
    List<String>? manufacturers,
    String? error,
    bool clearError = false,
  }) =>
      PartPickerState(
        loading: loading ?? this.loading,
        all: all ?? this.all,
        query: query ?? this.query,
        results: results ?? this.results,
        generation: clearGeneration ? null : (generation ?? this.generation),
        manufacturer:
            clearManufacturer ? null : (manufacturer ?? this.manufacturer),
        generations: generations ?? this.generations,
        manufacturers: manufacturers ?? this.manufacturers,
        error: clearError ? null : (error ?? this.error),
      );

  // `all` is compared by identity (it is replaced, never mutated), so a
  // keystroke doesn't deep-compare hundreds of parts.
  @override
  List<Object?> get props => [
        loading,
        identityHashCode(all),
        query,
        identityHashCode(results),
        generation,
        manufacturer,
        generations,
        manufacturers,
        error,
      ];
}
