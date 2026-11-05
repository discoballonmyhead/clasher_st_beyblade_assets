import 'package:equatable/equatable.dart';

class StructureState extends Equatable {
  const StructureState({this.busy = false, this.error, this.message});

  final bool busy;
  final String? error;
  final String? message;

  @override
  List<Object?> get props => [busy, error, message];
}
