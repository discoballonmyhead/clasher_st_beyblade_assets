import 'package:equatable/equatable.dart';

class WikiState extends Equatable {
  const WikiState({this.running = false, this.lines = const [], this.message, this.error});

  final bool running;

  /// Engine / scraper log (last 400 lines).
  final List<String> lines;
  final String? message;
  final String? error;

  WikiState copyWith({bool? running, List<String>? lines, String? message, String? error}) => WikiState(
        running: running ?? this.running,
        lines: lines ?? this.lines,
        message: message,
        error: error,
      );

  @override
  List<Object?> get props => [running, lines, message, error];
}
