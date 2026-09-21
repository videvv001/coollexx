import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/photo_store.dart';
import '../../models/release.dart';
import '../../models/tcg_card.dart';
import '../../state/app_state.dart';
import 'confirm_dialog.dart';
import 'photo_editor_screen.dart';
import 'photo_source_sheet.dart';

/// Aspect ratios shared by every folder-cover surface (My Collection grid,
/// Edit Folder dialog, in-folder "Set cover photo"), so landscape and
/// portrait covers always mean the same shape everywhere.
const double kLandscapeCoverAspect = 4 / 3;
const double kPortraitCoverAspect = 5 / 7;

class CoverPickResult {
  const CoverPickResult({required this.croppedPath, this.autoOtherPath});

  /// The saved, cropped-to-[CoverPickResult]'s-own-aspect-ratio cover.
  final String croppedPath;

  /// A centered default crop of the same source photo for the *other*
  /// orientation, only produced when the caller asked for one (via
  /// `otherAspectRatio` on [pickCoverWithAutoFill]).
  final String? autoOtherPath;
}

/// Lets the user pick a source photo and crop it to [aspectRatio] via the
/// shared [PhotoEditorScreen]. When [otherAspectRatio] is given, also
/// produces a centered (no-interaction) crop of the same source for that
/// other orientation — so picking one image can default both covers
/// without forcing the user through cropping twice. Returns null if the
/// user backs out at either step.
Future<CoverPickResult?> pickCoverWithAutoFill(
  BuildContext context, {
  required double aspectRatio,
  required String title,
  double? otherAspectRatio,
  bool allowExistingCardPhoto = false,
  List<TcgCard> releaseCards = const [],
  String? currentImagePath,
}) async {
  final sourcePath = await pickPhotoSource(
    context,
    allowExistingCardPhoto: allowExistingCardPhoto,
    releaseCards: releaseCards,
    existingImagePath: currentImagePath,
  );
  if (sourcePath == null || !context.mounted) return null;
  // rootNavigator: true for the same reason as pickPhotoSource's
  // useRootNavigator above — this must land on whatever Navigator the
  // caller (e.g. the Edit Folder dialog) actually lives on.
  final cropped = await Navigator.of(context, rootNavigator: true).push<String>(
    MaterialPageRoute(
      builder: (_) => PhotoEditorScreen(
        sourcePath: sourcePath,
        aspectRatio: aspectRatio,
        title: title,
      ),
    ),
  );
  if (cropped == null) return null;
  final autoOther = otherAspectRatio == null
      ? null
      : await centerCropAndSave(sourcePath, otherAspectRatio);
  return CoverPickResult(croppedPath: cropped, autoOtherPath: autoOther);
}

/// Centered cover-crop of [sourcePath] to [aspectRatio], with no user
/// interaction. Returns the saved cropped path, or null if the source
/// photo can't be read.
Future<String?> centerCropAndSave(String sourcePath, double aspectRatio) async {
  final bytes = await File(sourcePath).readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final rect = centerCropRect(
    sourceWidth: decoded.width.toDouble(),
    sourceHeight: decoded.height.toDouble(),
    targetAspect: aspectRatio,
  );
  final cropped = img.copyCrop(
    decoded,
    x: rect.left.round(),
    y: rect.top.round(),
    width: math.max(1, rect.width.round()),
    height: math.max(1, rect.height.round()),
  );

  final dir = await getTemporaryDirectory();
  final outFile = File(p.join(dir.path, '${const Uuid().v4()}.jpg'));
  await outFile.writeAsBytes(img.encodeJpg(cropped, quality: 90));
  return PhotoStore.instance.save(outFile);
}

/// The largest centered rectangle of [targetAspect] that fits inside a
/// [sourceWidth] x [sourceHeight] image. Pure geometry, no image I/O — kept
/// separate from [centerCropAndSave] so the crop math can be tested without
/// decoding a real image.
Rect centerCropRect({
  required double sourceWidth,
  required double sourceHeight,
  required double targetAspect,
}) {
  final cropW = math.min(sourceWidth, sourceHeight * targetAspect);
  final cropH = math.min(sourceHeight, sourceWidth / targetAspect);
  final x = (sourceWidth - cropW) / 2;
  final y = (sourceHeight - cropH) / 2;
  return Rect.fromLTWH(x, y, cropW, cropH);
}

/// Deletes [oldPath] unless it's still referenced by [keepIfAny] — used
/// when replacing one cover slot to avoid deleting a file another slot (or
/// the legacy single-cover fallback) still points at.
Future<void> deleteCoverIfOrphaned(
  String? oldPath,
  Iterable<String?> keepIfAny,
) async {
  if (oldPath == null) return;
  if (keepIfAny.contains(oldPath)) return;
  await PhotoStore.instance.delete(oldPath);
}

/// Confirms with the user, then deletes [release] together with every card
/// filed under it (its "collection entries" — this app has no separate
/// master/reference card table, so a release's cards ARE its collection)
/// and the release's own cover image files. Returns true if the release was
/// deleted, false if the user canceled or the deletion failed.
Future<bool> confirmAndDeleteRelease(
  BuildContext context,
  AppState state,
  Release release, {
  required int cardCount,
}) async {
  final confirmed = await confirmDelete(
    context,
    title: 'Delete folder?',
    message: cardCount > 0
        ? 'Deleting "${release.name}" will also delete $cardCount '
              'card${cardCount == 1 ? '' : 's'} from your collection. This '
              'action cannot be undone.'
        : 'Delete "${release.name}"? This action cannot be undone.',
  );
  if (confirmed != true) return false;
  try {
    await state.deleteRelease(release.id);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(content: Text('Could not delete folder')),
        );
    }
    return false;
  }
  // The release row (and its cards) are already gone; these are just the
  // now-unreferenced cover files exclusively owned by this release.
  for (final path in {
    release.coverPhotoPath,
    release.landscapeCoverPath,
    release.portraitCoverPath,
  }) {
    if (path != null) await PhotoStore.instance.delete(path);
  }
  return true;
}
