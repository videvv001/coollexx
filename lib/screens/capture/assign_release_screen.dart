import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import 'capture_route.dart';

/// 1a step 3 — Assign to release. Unassigned shots simply stay in the
/// unsorted tray if the user backs out here.
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

  @override
  void initState() {
    super.initState();
    _releaseId = widget.initialReleaseId;
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
      setState(() => _releaseId = release.id);
    }
  }

  Future<void> _save(AppState state) async {
    await state.moveCards(
      widget.cardIds,
      releaseId: _releaseId,
      clearRelease: _releaseId == null,
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
        onChanged: (v) => setState(() => _releaseId = v),
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
