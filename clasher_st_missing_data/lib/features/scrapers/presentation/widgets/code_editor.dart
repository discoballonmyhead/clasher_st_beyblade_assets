import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A plain code editor: monospace, line numbers, Tab inserts spaces, an error line highlighted in the gutter.
class CodeEditor extends StatefulWidget {
  const CodeEditor({super.key, required this.text, required this.onChanged, this.errorLine, this.readOnly = false});

  final String text;
  final ValueChanged<String> onChanged;
  final int? errorLine;
  final bool readOnly;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  late final _ctl = TextEditingController(text: widget.text);
  final _scroll = ScrollController();
  final _focus = FocusNode();
  static const _style = TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.4);

  @override
  void didUpdateWidget(CodeEditor old) {
    super.didUpdateWidget(old);
    if (widget.text != _ctl.text) {
      _ctl.value = TextEditingValue(text: widget.text, selection: const TextSelection.collapsed(offset: 0));
    }
    if (widget.errorLine != null && widget.errorLine != old.errorLine) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          final y = ((widget.errorLine! - 6).clamp(0, 1 << 20)) * 13 * 1.4;
          _scroll.jumpTo(y.clamp(0, _scroll.position.maxScrollExtent));
        }
      });
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.tab && !widget.readOnly) {
      final sel = _ctl.selection;
      final t = _ctl.text.replaceRange(sel.start, sel.end, '    ');
      _ctl.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: sel.start + 4));
      widget.onChanged(t);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = '\n'.allMatches(_ctl.text).length + 1;
    return Container(
      decoration: BoxDecoration(border: Border.all(color: cs.outlineVariant), borderRadius: BorderRadius.circular(6)),
      child: SingleChildScrollView(
        controller: _scroll,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            color: cs.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 1; i <= lines; i++)
                Text('$i',
                    style: _style.copyWith(
                      color: i == widget.errorLine ? cs.error : cs.outline,
                      fontWeight: i == widget.errorLine ? FontWeight.w800 : null,
                    )),
            ]),
          ),
          Expanded(
            child: Focus(
              onKeyEvent: _onKey,
              child: TextField(
                controller: _ctl,
                focusNode: _focus,
                readOnly: widget.readOnly,
                maxLines: null,
                style: _style,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.fromLTRB(10, 12, 10, 12),
                ),
                onChanged: widget.onChanged,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
