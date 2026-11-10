/// What the app must do about its own version.
enum UpdateRequirement {
  /// Nothing to do.
  none,

  /// A newer version exists; the user may update or dismiss.
  optional,

  /// This version is no longer supported; the app must be blocked until the
  /// user updates.
  required,
}

/// Decides whether the running app must / may be updated.
///
/// ## TODO(F2) - implement
///
/// Contract (hidden tests check this exactly - see ASSIGNMENT.md, Feature 2):
/// * Versions are dotted numbers like `1.4.0`, `1.10.2`, `2.0`. Compare them
///   numerically, segment by segment. Missing segments count as 0
///   (`1.4` == `1.4.0`).
/// * `current < minSupported`  -> [UpdateRequirement.required]
/// * `current < latest`        -> [UpdateRequirement.optional]
/// * otherwise                 -> [UpdateRequirement.none]
/// * If ANY of the three versions is malformed (empty, letters, negative
///   numbers, ...) return [UpdateRequirement.none]. A bad value in the
///   config console must never lock users out of the app.
class UpdatePolicy {
  const UpdatePolicy._();

  static UpdateRequirement evaluate({
    required String currentVersion,
    required String minSupportedVersion,
    required String latestVersion,
  }) {
    final current = _parse(currentVersion);
    final minimum = _parse(minSupportedVersion);
    final latest = _parse(latestVersion);
    if (current == null || minimum == null || latest == null) {
      return UpdateRequirement.none;
    }
    if (_compare(current, minimum) < 0) return UpdateRequirement.required;
    if (_compare(current, latest) < 0) return UpdateRequirement.optional;
    return UpdateRequirement.none;
  }

  static List<int>? _parse(String version) {
    if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(version)) return null;
    return version.split('.').map(int.parse).toList();
  }

  static int _compare(List<int> left, List<int> right) {
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final a = i < left.length ? left[i] : 0;
      final b = i < right.length ? right[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return 0;
  }
}
