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
  String? existingImagePath,
}) {
  return showModalBottomSheet<String>(
    context: context,
    // Matches showDialog's own default (true): callers that open this from
    // inside a dialog — e.g. Edit Folder — live on the app's root Navigator,
    // while the calling context may be a tab's own nested Navigator (see
    // AppShell). Without this, the sheet resolves to the nearest Navigator
    // to `context` and can end up on a different Overlay layer than the
    // dialog that opened it, rendering behind it instead of above it.
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (context) => _PhotoSourceSheet(
      allowExistingCardPhoto: allowExistingCardPhoto,
      releaseCards: releaseCards,
      existingImagePath: existingImagePath,
    ),
  );
}

class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet({
    required this.allowExistingCardPhoto,
    required this.releaseCards,
    this.existingImagePath,
  });

  final bool allowExistingCardPhoto;
  final List<TcgCard> releaseCards;
  final String? existingImagePath;

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
            if (existingImagePath != null)
              ListTile(
                leading: const Icon(Icons.crop_outlined),
                title: const Text('Adjust image'),
                // Re-opens the existing image in the same crop/reposition
                // screen the other two options end up in, rather than
                // re-picking a source — see PhotoEditorScreen via
                // pickCoverWithAutoFill.
                onTap: () => Navigator.pop(context, existingImagePath),
              ),
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
