import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/workbook.dart';
import '../../domain/usecases/workbook_usecases.dart';
import 'formatting.dart';

/// Rows edited most recently (by hand, auto-fill, images or the scraper). Returns the one picked.
Future<RecentEdit?> showRecentEditsDialog(BuildContext context) => showDialog<RecentEdit>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Recently edited'),
        content: SizedBox(
          width: 640,
          height: 460,
          child: FutureBuilder(
            future: sl<GetRecentEdits>()(limit: 100),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return snap.data!.fold(
                (f) => Center(child: Text(f.message)),
                (edits) => edits.isEmpty
                    ? const Center(child: Text('Nothing has been edited yet.'))
                    : ListView(children: [
                        for (final e in edits)
                          ListTile(
                            leading: const Icon(Icons.history),
                            title: Text('#${e.id}  ${e.name}'),
                            subtitle: Text(e.sheet),
                            trailing: Text(formatWhen(e.updatedAt)),
                            onTap: () => Navigator.pop(context, e),
                          ),
                      ]),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
