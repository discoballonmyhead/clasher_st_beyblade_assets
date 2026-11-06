import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/wiki/wiki_cubit.dart';
import '../cubits/wiki/wiki_state.dart';

/// Engine / scraper log at the bottom; collapsible.
class LogPanel extends StatefulWidget {
  const LogPanel({super.key});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  bool _open = true;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocConsumer<WikiCubit, WikiState>(
      listenWhen: (a, b) => a.lines.length != b.lines.length,
      listener: (_, _) => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }),
      builder: (context, s) => Column(mainAxisSize: MainAxisSize.min, children: [
        Material(
          color: cs.surfaceContainerHigh,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                Icon(_open ? Icons.expand_more : Icons.expand_less, size: 18),
                const SizedBox(width: 6),
                Text('Log (${s.lines.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (s.running) ...[
                  const SizedBox(width: 12),
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 6),
                  const Text('wiki fill running'),
                  TextButton(onPressed: context.read<WikiCubit>().stop, child: const Text('Stop')),
                ],
                const Spacer(),
                TextButton(onPressed: context.read<WikiCubit>().clearLog, child: const Text('Clear')),
              ]),
            ),
          ),
        ),
        if (_open)
          Container(
            height: 140,
            color: const Color(0xFF151922),
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemCount: s.lines.length,
              itemBuilder: (_, i) => Text(s.lines[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFD7DCE5))),
            ),
          ),
      ]),
    );
  }
}
