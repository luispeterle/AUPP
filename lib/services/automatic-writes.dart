import 'dart:async';

/// Marks database writes the app makes on its own (Dinzo and extension syncs,
/// recurring records), as opposed to what the user did. Any device can redo
/// them, so the hybrid sync never treats them as changes to send. The mark
/// follows the async call chain (a [Zone]), so a user edit happening at the
/// same time is still seen as the user's.
class AutomaticWrites {
  static const _key = #automaticWrite;

  static Future<T> run<T>(Future<T> Function() body) =>
      runZoned(body, zoneValues: {_key: true});

  static bool get active => Zone.current[_key] == true;
}
