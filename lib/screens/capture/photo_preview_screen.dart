import 'dart:io';

import 'package:flutter/material.dart';

import '../shared/photo_editor_screen.dart';

/// Full-screen, pinch-to-zoom preview for a single captured photo — pushed
/// from the small thumbnails in the burst strip and batch-triage list, where
/// there's no other way to check a shot before committing to it. "Edit"
/// routes into the shared crop/zoom/rotate editor; if it returns an edited
/// path, this screen pops with that path so the caller can swap it in. A
/// plain back-arrow pop returns `null` — no change.
class PhotoPreviewScreen extends StatelessWidget {
  const PhotoPreviewScreen({super.key, required this.path});

  final String path;

  Future<void> _edit(BuildContext context) async {
    final edited = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoEditorScreen(sourcePath: path, aspectRatio: 5 / 7),
      ),
    );
    if (edited != null && context.mounted) Navigator.pop(context, edited);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: () => _edit(context),
            child: const Text('Edit', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: Image.file(File(path)),
        ),
      ),
    );
  }
}
