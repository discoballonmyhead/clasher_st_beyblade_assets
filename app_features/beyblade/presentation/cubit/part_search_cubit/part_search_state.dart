part of 'part_search_cubit.dart';

sealed class PartSearchState extends Equatable {
  const PartSearchState();
  @override
  List<Object?> get props => [];
}

class PartSearchEmpty extends PartSearchState {
  const PartSearchEmpty();
}

class PartSearchLoading extends PartSearchState {
  const PartSearchLoading();
}

class PartSearchResults extends PartSearchState {
  const PartSearchResults(this.results);
  final List<BeybladePart> results;
  @override
  List<Object?> get props => [results];
}

class PartSearchError extends PartSearchState {
  const PartSearchError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}
