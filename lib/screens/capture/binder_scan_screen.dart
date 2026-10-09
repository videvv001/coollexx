import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../data/binder_page_detector.dart';
import '../../data/photo_store.dart';
import '../../models/capture_item.dart';
import '../../state/app_state.dart';
import '../shared/confirm_dialog.dart';
import '../shared/unsaved_capture_dialog.dart';
import 'batch_triage_screen.dart';

/// Where a page came into the session from. Recorded only to label it in
/// review — both sources run the identical pipeline from [_processOne] on.
enum BinderSource {
  camera('Photo'),
  upload('Upload');

  const BinderSource(this.label);
  final String label;
}

/// One binder page that has been scanned, with the crops it produced.
///
/// `items` are already durably in the capture session; this object is the
/// in-memory record of *which page each one came from*, which is what makes
/// "Page 2 — 9 cards" and removing a whole page possible.
///
/// ponytail: page grouping is in memory only. Surviving process death would
/// mean a `pageId` column on `capture_items` and a schema migration, to buy
/// back only the grouping — the crops themselves are already safe, and
/// `AppShell`'s recovery hands them back as one flat batch, which commits
/// and triages exactly the same. Add the column if page grouping ever needs
/// to outlive the screen.
class _ScannedPage {
  _ScannedPage({
    required this.id,
    required this.source,
    required this.scan,
    required this.items,
  });

  final String id;
  final BinderSource source;
  final BinderPageScan scan;
  final List<CaptureItem> items;
}

/// A page that couldn't be processed. Kept visible with its source path so
/// it can be retried or dismissed, rather than silently dropped.
class _FailedPage {
  const _FailedPage({
    required this.sourcePath,
    required this.source,
    required this.message,
  });

  final String sourcePath;
  final BinderSource source;
  final String message;
}

/// Scan Binder — photograph or upload binder pages and let the app find the
/// individual cards on them.
///
/// This sits *alongside* the single-card camera flow (`CaptureScreen`),
/// which is untouched. Binder Scan's own job ends at the crops: from there
/// each one goes through exactly the path a single captured photo does —
/// saved by `PhotoStore`, held in a `CaptureSession` until the user commits,
/// then `BatchTriageScreen` for OCR autofill, naming and assigning. There is
/// no second card model, save path or recognition route, and camera and
/// upload converge on one line of work ([_processOne]) before any of it.
///
/// Crops are persisted the moment they're produced, so a scanned page
/// survives navigating away, backgrounding and process death the same way a
/// burst shot does — including `AppShell`'s startup recovery, which reopens
/// a leftover session on the camera screen. Landing there after a binder
/// scan is odd-looking but correct: the pending items are ordinary card
/// photos, and "Done · review" commits them exactly as it would a burst.
/// Telling the two apart would mean a new column on `capture_sessions` to
/// buy nothing.
class BinderScanScreen extends StatefulWidget {
  const BinderScanScreen({super.key, this.boundReleaseId});

  /// The release cards from this scan should be filed into, mirroring
  /// `CaptureScreen.boundReleaseId` — it becomes the capture session's
  /// `targetReleaseId`, which is what `commit` files the cards under.
  final String? boundReleaseId;

  @override
  State<BinderScanScreen> createState() => _BinderScanScreenState();
}

class _BinderScanScreenState extends State<BinderScanScreen> {
  static const _uuid = Uuid();

  final List<_ScannedPage> _pages = [];
  final List<_FailedPage> _failed = [];

  /// Mirrors what's durably in the capture session, never the other way
  /// around: a crop only appears in [_pages] after `addItem` succeeds, per
  /// the same rule the camera screen follows for burst shots.
  String? _sessionId;

  ({int done, int total, int lastCount})? _progress;
  bool _committing = false;

  int get _cardCount => _pages.fold(0, (sum, page) => sum + page.items.length);

  Future<void> _takePhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.camera);
    if (file == null) return;
    await _processAll([file.path], BinderSource.camera);
  }

  /// Several pages in one go — the system photo picker's own multi-select,
  /// which on Android 13+ needs no storage permission at all.
  Future<void> _uploadImages() async {
    final files = await ImagePicker().pickMultiImage();
    if (files.isEmpty) return;
    await _processAll([for (final f in files) f.path], BinderSource.upload);
  }

  /// Pages are processed strictly one at a time, and each one's full-size
  /// bitmap lives and dies inside its own isolate run. Twenty selected
  /// images therefore cost one decode's worth of memory, not twenty — and
  /// the UI keeps painting progress throughout because none of the work
  /// happens on this thread.
  Future<void> _processAll(List<String> paths, BinderSource source) async {
    setState(() => _progress = (done: 0, total: paths.length, lastCount: 0));
    for (var i = 0; i < paths.length; i++) {
      if (!mounted) return;
      setState(
        () => _progress = (
          done: i,
          total: paths.length,
          lastCount: _progress?.lastCount ?? 0,
        ),
      );
      final found = await _processOne(paths[i], source);
      if (!mounted) return;
      setState(
        () => _progress = (done: i + 1, total: paths.length, lastCount: found),
      );
    }
    if (mounted) setState(() => _progress = null);
  }

  /// The single pipeline both input methods feed: detect and crop on a
  /// background isolate, then persist each crop into the capture session.
  ///
  /// Returns how many cards this page yielded. A page that can't be read, or
  /// that yields nothing, is recorded as failed and leaves every page before
  /// it untouched — one bad image never costs the user the rest of a
  /// twenty-page upload.
  Future<int> _processOne(String path, BinderSource source) async {
    final BinderPageScan scan;
    try {
      scan = await scanBinderPage(path);
    } catch (e) {
      if (mounted) {
        setState(
          () => _failed.add(
            _FailedPage(
              sourcePath: path,
              source: source,
              message: e.toString(),
            ),
          ),
        );
      }
      return 0;
    }
    if (scan.cardJpgs.isEmpty) {
      if (mounted) {
        setState(
          () => _failed.add(
            _FailedPage(
              sourcePath: path,
              source: source,
              message: 'No cards detected on this page',
            ),
          ),
        );
      }
      return 0;
    }
    if (!mounted) return 0;
    return _addToSession(scan, source);
  }

  /// Writes this page's crops into permanent storage and records each one in
  /// the capture session. The session is created on the first page that
  /// actually yields cards rather than when the screen opens, so backing out
  /// of an empty scan leaves nothing behind.
  Future<int> _addToSession(BinderPageScan scan, BinderSource source) async {
    final state = context.read<AppState>();
    final paths = await saveCardCrops(scan.cardJpgs);
    var sessionId = _sessionId;
    final added = <CaptureItem>[];
    for (final path in paths) {
      try {
        sessionId ??= (await state.captureSessions.createSession(
          targetReleaseId: widget.boundReleaseId,
        )).id;
        added.add(await state.captureSessions.addItem(sessionId, path));
      } catch (_) {
        // The crop file is fine but nothing can ever find it again, so it's
        // deleted rather than orphaned — and not counted. Every crop that
        // did make it stays exactly as it was.
        await PhotoStore.instance.delete(path);
      }
    }
    if (!mounted) return added.length;
    setState(() {
      _sessionId = sessionId;
      _pages.add(
        _ScannedPage(id: _uuid.v4(), source: source, scan: scan, items: added),
      );
    });
    _syncPendingCapture();
    return added.length;
  }

  /// Keeps `AppState` told how much unsaved work is outstanding, which is
  /// what lets the bottom nav bar prompt before switching tabs without
  /// reaching into this screen — the same mirror the camera screen keeps.
  void _syncPendingCapture() {
    final sessionId = _sessionId;
    final state = context.read<AppState>();
    state.setPendingCapture(
      sessionId == null || _cardCount == 0
          ? null
          : PendingCapture(sessionId: sessionId, count: _cardCount),
    );
  }

  Future<void> _retryFailed(_FailedPage failed) async {
    setState(() => _failed.remove(failed));
    await _processAll([failed.sourcePath], failed.source);
  }

  /// Drops one wrongly detected card — a glare patch, a slice of the binder
  /// itself — before any of it reaches the collection.
  Future<void> _removeCard(_ScannedPage page, int index) async {
    final state = context.read<AppState>();
    final item = page.items[index];
    await state.captureSessions.removeItem(item);
    if (!mounted) return;
    setState(() => page.items.removeAt(index));
    if (page.items.isEmpty) setState(() => _pages.remove(page));
    await _discardSessionIfEmpty();
  }

  Future<void> _removePage(_ScannedPage page) async {
    final confirmed = await confirmDelete(
      context,
      title: 'Remove this page?',
      message:
          'Drops all ${page.items.length} cards found on it. The pages '
          'around it are kept.',
      confirmLabel: 'Remove',
    );
    if (!confirmed || !mounted) return;
    final state = context.read<AppState>();
    for (final item in page.items) {
      await state.captureSessions.removeItem(item);
    }
    if (!mounted) return;
    setState(() => _pages.remove(page));
    await _discardSessionIfEmpty();
  }

  /// A session with nothing left in it is deleted outright rather than left
  /// as an empty row that app-start recovery would only have to clean up.
  Future<void> _discardSessionIfEmpty() async {
    final sessionId = _sessionId;
    if (sessionId == null || _cardCount > 0) {
      _syncPendingCapture();
      return;
    }
    await context.read<AppState>().captureSessions.discard(sessionId);
    if (!mounted) return;
    setState(() => _sessionId = null);
    _syncPendingCapture();
  }

  /// Commits the session — turning every crop into a real collection entry
  /// via the same `CaptureSessionRepository.commit` a burst uses — and hands
  /// the new cards to batch triage, where OCR autofill, renaming, binning
  /// and assigning all already live.
  Future<void> _reviewAll() async {
    final sessionId = _sessionId;
    if (sessionId == null) return;
    final state = context.read<AppState>();
    final navigator = Navigator.of(context);
    setState(() => _committing = true);
    final cards = await state.captureSessions.commit(
      state.collection,
      sessionId,
    );
    await state.refresh();
    if (!mounted) return;
    state.setPendingCapture(null);
    setState(() {
      _committing = false;
      _sessionId = null;
      _pages.clear();
      _failed.clear();
    });
    if (cards.isEmpty) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => BatchTriageScreen(
          cardIds: cards.map((c) => c.id).toList(),
          boundReleaseId: widget.boundReleaseId,
        ),
      ),
    );
  }

  /// Leaving with crops that aren't in the collection yet, via Android back
  /// or the close button — the same three-way choice, and the same dialogs,
  /// the camera screen offers for an unsaved burst.
  Future<bool> _resolveLeaveConfirmation() async {
    final state = context.read<AppState>();
    final count = _cardCount;
    final action = await showUnsavedCaptureDialog(context, count: count);
    if (!mounted) return false;
    switch (action) {
      case LeaveCaptureAction.continueCapturing:
        return false;
      case LeaveCaptureAction.discard:
        final confirmed = await confirmDiscardCapture(context, count);
        if (!confirmed || !mounted) return false;
        await state.captureSessions.discard(_sessionId!);
      case LeaveCaptureAction.saveAndLeave:
        await state.captureSessions.commit(state.collection, _sessionId!);
        await state.refresh();
    }
    if (!mounted) return false;
    state.setPendingCapture(null);
    setState(() {
      _sessionId = null;
      _pages.clear();
      _failed.clear();
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final hasContent = _pages.isNotEmpty || _failed.isNotEmpty;
    return PopScope(
      canPop: _cardCount == 0,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _resolveLeaveConfirmation() && mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Scan binder'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
        body: progress != null
            ? _Progress(progress: progress)
            : !hasContent
            ? _Sources(onCamera: _takePhoto, onUpload: _uploadImages)
            : _Review(
                pages: _pages,
                failed: _failed,
                cardCount: _cardCount,
                onRemoveCard: _removeCard,
                onRemovePage: _removePage,
                onRetryFailed: _retryFailed,
                onDismissFailed: (f) => setState(() => _failed.remove(f)),
              ),
        bottomNavigationBar: progress != null || !hasContent
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _cardCount == 0 || _committing
                              ? null
                              : _reviewAll,
                          child: _committing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text('Review all $_cardCount cards →'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _committing ? null : _takePhoto,
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: const Text('Another page'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _committing ? null : _uploadImages,
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('Upload more'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Per-page progress through a multi-image selection, in the shape the user
/// actually cares about: which page, out of how many, and what it found.
class _Progress extends StatelessWidget {
  const _Progress({required this.progress});

  final ({int done, int total, int lastCount}) progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = (progress.done + 1).clamp(1, progress.total);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              progress.total == 1
                  ? 'Finding cards on the page…'
                  : 'Processing binder pages…',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 20),
            LinearProgressIndicator(
              value: progress.total == 0
                  ? null
                  : progress.done / progress.total,
            ),
            const SizedBox(height: 12),
            if (progress.total > 1)
              Text(
                'Page $current of ${progress.total}',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            if (progress.done > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${progress.lastCount} cards detected',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The two ways in. Both end up in the same `_processOne`.
class _Sources extends StatelessWidget {
  const _Sources({required this.onCamera, required this.onUpload});

  final VoidCallback onCamera;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.grid_view_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'Photograph a whole binder page and the app will pick out each '
              'card on it. Add as many pages as you like before saving.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take binder photo'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Upload binder image(s)'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Everything scanned so far, page by page. Built with a `ListView.builder`
/// so a twenty-page session only ever builds and decodes the pages actually
/// on screen.
class _Review extends StatelessWidget {
  const _Review({
    required this.pages,
    required this.failed,
    required this.cardCount,
    required this.onRemoveCard,
    required this.onRemovePage,
    required this.onRetryFailed,
    required this.onDismissFailed,
  });

  final List<_ScannedPage> pages;
  final List<_FailedPage> failed;
  final int cardCount;
  final void Function(_ScannedPage page, int index) onRemoveCard;
  final void Function(_ScannedPage page) onRemovePage;
  final void Function(_FailedPage failed) onRetryFailed;
  final void Function(_FailedPage failed) onDismissFailed;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      itemCount: pages.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _header(context);
        final page = pages[index - 1];
        return _PageSection(
          page: page,
          number: index,
          onRemoveCard: (i) => onRemoveCard(page, i),
          onRemovePage: () => onRemovePage(page),
        );
      },
    );
  }

  Widget _header(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$cardCount card${cardCount == 1 ? '' : 's'} detected',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        Text(
          'across ${pages.length} page${pages.length == 1 ? '' : 's'}',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        for (final f in failed)
          Card(
            margin: const EdgeInsets.only(top: 12),
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      f.message,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                  TextButton(
                    onPressed: () => onRetryFailed(f),
                    child: const Text('Retry'),
                  ),
                  IconButton(
                    tooltip: 'Dismiss',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => onDismissFailed(f),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PageSection extends StatelessWidget {
  const _PageSection({
    required this.page,
    required this.number,
    required this.onRemoveCard,
    required this.onRemovePage,
  });

  final _ScannedPage page;
  final int number;
  final ValueChanged<int> onRemoveCard;
  final VoidCallback onRemovePage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Page $number — ${page.items.length} card'
                '${page.items.length == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              page.source.label,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
            IconButton(
              tooltip: 'Remove page',
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemovePage,
            ),
          ],
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: page.scan.pageWidth / page.scan.pageHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // cacheWidth keeps a 900px page decoding at roughly the size
                // it's drawn, which is what stops a long session's worth of
                // page images adding up in the image cache.
                Image.memory(
                  page.scan.pageJpg,
                  fit: BoxFit.fill,
                  cacheWidth: 600,
                ),
                CustomPaint(
                  painter: _QuadPainter(
                    quads: page.scan.quads,
                    pageSize: Size(
                      page.scan.pageWidth.toDouble(),
                      page.scan.pageHeight.toDouble(),
                    ),
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 5 / 7,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: page.items.length,
          itemBuilder: (context, i) => _CropTile(
            path: page.items[i].path,
            number: i + 1,
            color: scheme.primary,
            onRemove: () => onRemoveCard(i),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 16),
          child: Divider(height: 1),
        ),
      ],
    );
  }
}

/// One cropped card, read back from the file it was saved to rather than
/// held in memory — a twenty-page session's crops would be well over a
/// hundred megabytes of bitmap otherwise.
class _CropTile extends StatelessWidget {
  const _CropTile({
    required this.path,
    required this.number,
    required this.color,
    required this.onRemove,
  });

  final String path;
  final int number;
  final Color color;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(path), fit: BoxFit.cover, cacheWidth: 240),
          Positioned(
            left: 4,
            top: 4,
            child: _Badge(color: color, child: Text('$number')),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              tooltip: 'Not a card',
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
        child: child,
      ),
    );
  }
}

/// Draws each detected quad over its page, numbered in the same order the
/// crops below it are listed. Quads are in page-image pixels, so everything
/// scales by the ratio between that and the space this paints into.
class _QuadPainter extends CustomPainter {
  const _QuadPainter({
    required this.quads,
    required this.pageSize,
    required this.color,
  });

  final List<CardQuad> quads;
  final Size pageSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / pageSize.width;
    final sy = size.height / pageSize.height;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final corner = Paint()..color = color;

    for (final quad in quads) {
      final pts = quad.corners
          .map((c) => Offset(c.dx * sx, c.dy * sy))
          .toList();
      canvas.drawPath(Path()..addPolygon(pts, true), stroke);
      // The first corner is drawn larger: it's the card's own top-left, so
      // a crop that came out rotated is diagnosable from the overlay alone.
      for (var i = 0; i < pts.length; i++) {
        canvas.drawCircle(pts[i], i == 0 ? 5 : 3, corner);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QuadPainter old) =>
      old.quads != quads || old.pageSize != pageSize || old.color != color;
}
