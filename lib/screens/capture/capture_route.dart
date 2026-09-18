/// Shared route name so screens deep in the capture flow (batch triage,
/// assign-to-release, name/tag/file) can pop back to the camera screen —
/// or past it, back to whatever launched capture — without each one
/// importing capture_screen.dart and creating an import cycle.
const captureRouteName = '/capture';
