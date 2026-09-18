import 'dart:io';

import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom viewer for one or more card images, with
/// swipe navigation and a "i / N" position indicator when there's more than
/// one. Reused anywhere a card's photos are shown at thumbnail size.
Future<void> openCardImageViewer(
  BuildContext context,
  List<String> paths, {
  int initialIndex = 0,
}) {
  if (paths.isEmpty) return Future.value();
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CardImageViewer(paths: paths, initialIndex: initialIndex),
      fullscreenDialog: true,
    ),
  );
}

class CardImageViewer extends StatefulWidget {
  const CardImageViewer({super.key, required this.paths, this.initialIndex = 0});

  final List<String> paths;
  final int initialIndex;

  @override
  State<CardImageViewer> createState() => _CardImageViewerState();
}

class _CardImageViewerState extends State<CardImageViewer> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (widget.paths.length > 1)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${_index + 1} / ${widget.paths.length}',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.paths.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, index) => Center(
              child: InteractiveViewer(
                maxScale: 4,
                child: Image.file(File(widget.paths[index])),
              ),
            ),
          ),
          if (widget.paths.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.paths.length; i++)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
