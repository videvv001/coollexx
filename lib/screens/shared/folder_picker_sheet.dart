import 'package:flutter/material.dart';

import '../../models/release.dart';
import '../../state/app_state.dart';
import '../../widgets/photo_placeholder.dart';
import 'folder_cover.dart';

/// Bottom sheet for choosing a destination folder for Move/Copy — cover
/// thumbnail + name + card count, with a search field once there are enough
/// folders to make one useful. Returns the chosen release id, or null if the
/// user backs out.
Future<String?> pickDestinationFolder(
  BuildContext context, {
  required AppState state,
  required String title,
  String? excludeReleaseId,
}) {
  final options = state.releases.where((r) => r.id != excludeReleaseId).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) =>
        _FolderPickerSheet(title: title, options: options, state: state),
  );
}

class _FolderPickerSheet extends StatefulWidget {
  const _FolderPickerSheet({
    required this.title,
    required this.options,
    required this.state,
  });

  final String title;
  final List<Release> options;
  final AppState state;

  @override
  State<_FolderPickerSheet> createState() => _FolderPickerSheetState();
}

class _FolderPickerSheetState extends State<_FolderPickerSheet> {
  final _queryController = TextEditingController();
  final Map<String, int> _counts = {};

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    for (final r in widget.options) {
      _counts[r.id] = await widget.state.collection.cardCountInRelease(r.id);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.options
        : widget.options
              .where((r) => r.name.toLowerCase().contains(query))
              .toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            if (widget.options.length > 6)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _queryController,
                  decoration: const InputDecoration(
                    hintText: 'Search folders',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            const SizedBox(height: 8),
            Flexible(
              child: widget.options.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No other folders yet'),
                    )
                  : filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No folders match'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final release = filtered[index];
                        return ListTile(
                          leading: SizedBox(
                            width: 44,
                            child: PhotoPlaceholder(
                              path: release.displayLandscapeCover,
                              aspectRatio: kLandscapeCoverAspect,
                              icon: Icons.folder_outlined,
                              borderRadius: 6,
                            ),
                          ),
                          title: Text(release.name),
                          subtitle: Text('${_counts[release.id] ?? 0} cards'),
                          trailing: release.isFavorite
                              ? const Icon(
                                  Icons.star,
                                  size: 18,
                                  color: Colors.amber,
                                )
                              : null,
                          onTap: () => Navigator.pop(context, release.id),
                        );
                      },
                    ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
