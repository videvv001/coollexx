import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/sub_folder.dart';
import '../../state/app_state.dart';
import 'capture_route.dart';

/// 1a step 3 — Assign to release. Sub-folder is explicitly optional and
/// defaults to none; unassigned shots simply stay in the unsorted tray if
/// the user backs out here.
class AssignReleaseScreen extends StatefulWidget {
  const AssignReleaseScreen({
    super.key,
    required this.cardIds,
    this.initialReleaseId,
  });

  final List<String> cardIds;
  final String? initialReleaseId;

  @override
  State<AssignReleaseScreen> createState() => _AssignReleaseScreenState();
}

class _AssignReleaseScreenState extends State<AssignReleaseScreen> {
  String? _releaseId;
  String? _subFolderId;
  List<SubFolder> _subFolders = [];

  @override
  void initState() {
    super.initState();
    _releaseId = widget.initialReleaseId;
    if (_releaseId != null) _loadSubFolders();
  }

  Future<void> _loadSubFolders() {
    final state = context.read<AppState>();
    return state.collection.subFoldersFor(_releaseId!).then((v) {
      if (mounted) setState(() => _subFolders = v);
    });
  }

  Future<void> _newRelease(AppState state) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New release folder'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final release = await state.createRelease(name);
      setState(() {
        _releaseId = release.id;
        _subFolderId = null;
        _subFolders = [];
      });
    }
  }

  Future<void> _save(AppState state) async {
    await state.moveCards(
      widget.cardIds,
      releaseId: _releaseId,
      clearRelease: _releaseId == null,
      subFolderId: _subFolderId,
      clearSubFolder: _subFolderId == null,
    );
    if (!mounted) return;
    Navigator.of(context).popUntil(ModalRoute.withName(captureRouteName));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final matchingReleases = state.releases.where((r) => r.id == _releaseId);
    final releaseName = matchingReleases.isEmpty
        ? null
        : matchingReleases.first.name;

    return Scaffold(
      appBar: AppBar(title: Text('Assign ${widget.cardIds.length} cards')),
      body: RadioGroup<String>(
        groupValue: _releaseId,
        onChanged: (v) {
          setState(() {
            _releaseId = v;
            _subFolderId = null;
          });
          _loadSubFolders();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final release in state.releases)
              RadioListTile<String>(
                value: release.id,
                title: Text(release.name),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('New release…'),
              onTap: () => _newRelease(state),
            ),
            if (_releaseId != null) ...[
              const Divider(height: 32),
              Text(
                'Sub-folder — optional',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('None'),
                    selected: _subFolderId == null,
                    onSelected: (_) => setState(() => _subFolderId = null),
                  ),
                  for (final sf in _subFolders)
                    ChoiceChip(
                      label: Text(sf.name),
                      selected: _subFolderId == sf.id,
                      onSelected: (_) => setState(() => _subFolderId = sf.id),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => _save(state),
              child: Text(
                _releaseId == null ? 'Leave unsorted' : 'Save to $releaseName',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
