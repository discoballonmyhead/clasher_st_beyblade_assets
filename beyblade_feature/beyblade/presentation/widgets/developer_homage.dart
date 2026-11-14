import 'dart:async';

import 'package:clasher_st/features/beyblade/presentation/pages/beyblade_home.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DeveloperHomage extends StatefulWidget {
  const DeveloperHomage({
    super.key,
    required this.entries,
    this.height = 190,
    this.autoPlayInterval = const Duration(seconds: 4),
    this.autoPlay = true,
    this.showIndicators = true,
    this.backgroundColor,
    this.borderRadius = 16,
    this.onEntryTap,
  });

  final List<DeveloperHomageEntry> entries;
  final double height;
  final Duration autoPlayInterval;
  final bool autoPlay;
  final bool showIndicators;
  final Color? backgroundColor;
  final double borderRadius;

  final ValueChanged<DeveloperHomageEntry>? onEntryTap;

  @override
  State<DeveloperHomage> createState() => _DeveloperHomageState();
}

class _DeveloperHomageState extends State<DeveloperHomage> {
  late final PageController _pageController;

  Timer? _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();

    _pageController = PageController();

    _startAutoPlay();
  }

  @override
  void didUpdateWidget(covariant DeveloperHomage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.entries.length != widget.entries.length ||
        oldWidget.autoPlay != widget.autoPlay ||
        oldWidget.autoPlayInterval != widget.autoPlayInterval) {
      _currentIndex = 0;

      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }

      _startAutoPlay();
    }
  }

  void _startAutoPlay() {
    _timer?.cancel();

    if (!widget.autoPlay || widget.entries.length <= 1) return;

    _timer = Timer.periodic(widget.autoPlayInterval, (_) {
      if (!mounted || !_pageController.hasClients) return;

      final nextIndex = (_currentIndex + 1) % widget.entries.length;

      _pageController.animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _onPageChanged(int index) {
    if (!mounted) return;

    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _openEntry(DeveloperHomageEntry entry) async {
    widget.onEntryTap?.call(entry);

    if (widget.onEntryTap != null) return;

    final link = entry.link;

    if (link == null || link.isEmpty) return;

    final uri = Uri.tryParse(link);

    if (uri == null) return;

    try {
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // No external application available.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (widget.entries.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          widget.borderRadius,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? cs.surfaceContainerHighest,
          ),
          child: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                itemCount: widget.entries.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final entry = widget.entries[index];

                  return _DeveloperHomageSlide(
                    entry: entry,
                    onTap: () => _openEntry(entry),
                  );
                },
              ),
              if (widget.showIndicators && widget.entries.length > 1)
                Positioned(
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.entries.length,
                      (index) {
                        final selected = index == _currentIndex;

                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 3,
                          ),
                          height: 5,
                          width: selected ? 20 : 5,
                          decoration: BoxDecoration(
                            color: selected
                                ? widget.entries[_currentIndex].accentColor
                                : cs.onSurface.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeveloperHomageSlide extends StatelessWidget {
  const _DeveloperHomageSlide({
    required this.entry,
    required this.onTap,
  });

  final DeveloperHomageEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Right Side - Dedicated Image Area
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 160, // Dedicated width for the image
              child: ShaderMask(
                // Creates a smooth fade on the left edge of the image
                shaderCallback: (rect) {
                  return const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      Colors.black, // Solid area of the mask
                    ],
                    stops: [0.0, 0.25],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstIn,
                child: Container(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                  child: Image.asset(
                    entry.image,
                    fit: BoxFit.contain, // Never crops the image
                    alignment: Alignment.centerRight,
                    errorBuilder: (context, error, stackTrace) {
                      // Debug view: Tells you EXACTLY which file name is failing
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image,
                              color: entry.accentColor, size: 28),
                          const SizedBox(height: 6),
                          Text(
                            'Missing:\n${entry.image.split('/').last}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              color: entry.accentColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // 2. Left Side - Text Content
            Positioned(
              left: 16,
              top: 16,
              bottom: 25,
              right: 150, // Stops text before it hits the image area
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (entry.role != null && entry.role!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: entry.accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        entry.role!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: entry.accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  const SizedBox(height: 9),
                  Text(
                    entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.75),
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                  if (entry.link != null && entry.link!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Learn more',
                          style: TextStyle(
                            color: entry.accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.open_in_new,
                          size: 11,
                          color: entry.accentColor,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // 3. Accent strip
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 3,
                color: entry.accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
