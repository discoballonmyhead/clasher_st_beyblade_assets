import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Live output of background jobs, scrolled to the end.
class JobLog extends StatefulWidget {
  const JobLog({super.key, required this.lines, this.running = false, this.onStop, this.onClear, this.height = 220});

  final List<String> lines;
  final bool running;
  final VoidCallback? onStop;
  final VoidCallback? onClear;
  final double height;

  @override
  State<JobLog> createState() => _JobLogState();
}

class _JobLogState extends State<JobLog> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(JobLog old) {
    super.didUpdateWidget(old);
    if (old.lines.length != widget.lines.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFF15181E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
          child: Row(children: [
            Text('Log', style: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (widget.running) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
            const Spacer(),
            if (widget.running && widget.onStop != null)
              TextButton.icon(
                onPressed: widget.onStop,
                icon: Icon(Icons.stop, color: cs.error, size: 18),
                label: Text('Stop', style: TextStyle(color: cs.error)),
              ),
            IconButton(
              tooltip: 'Copy the log',
              icon: Icon(Icons.copy, size: 16, color: Colors.grey.shade400),
              onPressed: () => Clipboard.setData(ClipboardData(text: widget.lines.join('\n'))),
            ),
            if (widget.onClear != null)
              IconButton(
                tooltip: 'Clear',
                icon: Icon(Icons.clear_all, size: 18, color: Colors.grey.shade400),
                onPressed: widget.onClear,
              ),
          ]),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            itemCount: widget.lines.length,
            itemBuilder: (_, i) {
              final l = widget.lines[i];
              final color = l.contains('ERROR') || l.contains('STOPPED') || l.contains('error:')
                  ? const Color(0xFFFF8A80)
                  : l.contains('WARNING') || l.contains('warning')
                      ? const Color(0xFFFFD180)
                      : l.startsWith('──') || l.startsWith(r'$ ')
                          ? const Color(0xFF82B1FF)
                          : const Color(0xFFE0E0E0);
              return Text(l, style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: color));
            },
          ),
        ),
      ]),
    );
  }
}

/// A confirmation that spells out exactly what an outward-facing step will do.
Future<bool> confirmAction(BuildContext context, {required String title, required List<String> facts, required String action}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final f in facts) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('•  $f')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    ) ??
    false;
