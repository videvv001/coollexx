import 'dart:io';

import 'package:flutter/material.dart';

import '../shared/card_image_viewer.dart';
import '../../widgets/photo_placeholder.dart';

/// The large image area at the top of the card-detail screen: a swipeable
/// gallery with a "1/3" position badge, prev/next arrows (hidden at the
/// ends), and a copies badge. Tapping a page opens the existing full-screen
/// [CardImageViewer]. Not reused elsewhere — the thumbnail strips on other
/// screens use `PhotoPlaceholder`/`openCardImageViewer` directly.
class CardImageCarousel extends StatefulWidget {
  const CardImageCarousel({
    super.key,
    required this.paths,
    required this.copies,
  });

  final List<String> paths;
  final int copies;

  @override
  State<CardImageCarousel> createState() => _CardImageCarouselState();
}

class _CardImageCarouselState extends State<CardImageCarousel> {
  final _controller = PageController();
  int _index = 0;

  void _go(int delta) {
    _controller.animateToPage(
      _index + delta,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final paths = widget.paths;
    final hasMultiple = paths.length > 1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 5 / 7,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (paths.isEmpty)
              const PhotoPlaceholder(dashed: true, borderRadius: 0)
            else
              PageView.builder(
                controller: _controller,
                itemCount: paths.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () =>
                      openCardImageViewer(context, paths, initialIndex: i),
                  child: Image.file(File(paths[i]), fit: BoxFit.cover),
                ),
              ),
            if (hasMultiple) ...[
              if (_index > 0)
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _NavButton(
                      icon: Icons.chevron_left,
                      onTap: () => _go(-1),
                    ),
                  ),
                ),
              if (_index < paths.length - 1)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: _NavButton(
                      icon: Icons.chevron_right,
                      onTap: () => _go(1),
                    ),
                  ),
                ),
              Positioned(
                top: 12,
                right: 12,
                child: _Badge('${_index + 1}/${paths.length}'),
              ),
            ],
            Positioned(
              bottom: 12,
              right: 12,
              child: _Badge('Copies: ${widget.copies}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.35),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
