import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/tcg_card.dart';
import '../../widgets/photo_placeholder.dart';

/// Bottom sheet offering where a new photo comes from: camera, gallery, or
/// (optionally) an existing photo already on a card in the current release.
/// Returns a raw source path only — never touches `PhotoStore` itself, so
/// the caller always routes the result through `PhotoEditorScreen` first.
Future<String?> pickPhotoSource(
  BuildContext context, {
  bool allowExistingCardPhoto = false,
  List<TcgCard> releaseCards = const [],
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PhotoSourceSheet(
      allowExistingCardPhoto: allowExistingCardPhoto,
      releaseCards: releaseCards,
    ),
  );
}

class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet({
    required this.allowExistingCardPhoto,
    required this.releaseCards,
  });

  final bool allowExistingCardPhoto;
  final List<TcgCard> releaseCards;

  Future<void> _pick(BuildContext context, ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source);
    if (context.mounted) Navigator.pop(context, file?.path);
  }

  @override
  Widget build(BuildContext context) {
    final cardPhotos = releaseCards
        .where((c) => c.hasPhoto)
        .expand((c) => c.photoPaths)
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => _pick(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => _pick(context, ImageSource.gallery),
            ),
            if (allowExistingCardPhoto && cardPhotos.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Or use a photo already in this release'),
                ),
              ),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: cardPhotos.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final path = cardPhotos[index];
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, path),
                      child: SizedBox(
                        width: 80,
                        child: PhotoPlaceholder(
                          path: path,
                          aspectRatio: 1,
                          borderRadius: 10,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
