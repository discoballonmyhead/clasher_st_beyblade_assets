import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:equatable/equatable.dart';

class DeckSlotsState extends Equatable {
  const DeckSlotsState({this.loading = true, this.slots = const []});

  final bool loading;
  final List<ResolvedDeckSlot> slots;

  @override
  List<Object?> get props => [loading, slots];
}
