import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/beyblade_builder_content.dart';
import 'package:flutter/material.dart';

import 'beyblade_display_page.dart';

class BeyBuilderPage extends StatefulWidget {
  const BeyBuilderPage({super.key, this.initialLoadout, this.onBuildConfirmed});

  final BeybladeLoadout? initialLoadout;
  final ValueChanged<Beyblade>? onBuildConfirmed;

  @override
  State<BeyBuilderPage> createState() => _BeyBuilderPageState();
}

class _BeyBuilderPageState extends State<BeyBuilderPage> {
  BeybladeLoadout? _loadout;
  int _contentGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadout = widget.initialLoadout;
  }

  // Future<void> _buildFromCode() async {
  //   final controller = TextEditingController();
  //   final code = await AppDialogWidget.show<String>(
  //     context,
  //     title: TrTokens.buildFromCodeTitle.tr,
  //     content: TextField(
  //       controller: controller,
  //       autofocus: true,
  //       decoration: InputDecoration(hintText: TrTokens.pasteBuildCodeHint.tr),
  //     ),
  //     actionButton: FilledButton(
  //       onPressed: () =>
  //           Navigator.of(context, rootNavigator: true).pop(controller.text),
  //       child: Text(TrTokens.buildBtnTxt.tr),
  //     ),
  //     secondaryButton: OutlinedButton(
  //       onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
  //       child: Text(TrTokens.cancelTxt.tr),
  //     ),
  //   );
  //   if (code == null || code.trim().isEmpty || !mounted) return;

  //   try {
  //     final loadout = BeybladeLoadout.fromShareCode(code);
  //     setState(() {
  //       _loadout = loadout;
  //       _contentGeneration++;
  //     });
  //   } catch (_) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text(TrTokens.invalidCodeMsg.tr)),
  //       );
  //     }
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    return ResponsiveScaffold(
      alignment: Alignment
          .topCenter, // <-- Aligns content to the top instead of centering vertically
      maxWidth: rc.maxContentWidth,
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(TrTokens.beyBuilderTitle.tr),
        //TODO implement
        // actions: [
        //   IconButton(
        //     tooltip: TrTokens.buildFromCodeBtn.tr,
        //     icon: const Icon(Icons.qr_code_2_outlined),
        //     onPressed: _buildFromCode,
        //   ),
        // ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
            rc.horizontalPadding, rc.sm, rc.horizontalPadding, rc.md),
        child: BeybladeBuilderContent(
          key: ValueKey(_contentGeneration),
          initialLoadout: _loadout,
          onConfirm: (Beyblade beyblade) {
            if (widget.onBuildConfirmed != null) {
              widget.onBuildConfirmed!(beyblade);
            } else {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => BeybladeDisplayPage(beyblade: beyblade)));
            }
          },
        ),
      ),
    );
  }
}
