/// Tunable draft topology defaults and the SharedPreferences keys used by the
/// debug-only capacity overrides on the create/join screens.
class DraftConfig {
  DraftConfig._();

  static const int defaultMaxDirectLinks = 4;
  static const int defaultRelayMaxChildren = 3;

  static const int minMaxDirectLinks = 1;
  static const int maxMaxDirectLinks = 8;
  static const int minRelayMaxChildren = 1;
  static const int maxRelayMaxChildren = 5;

  static const String prefMaxDirectLinks = 'draft_debug_max_direct_links';
  static const String prefRelayMaxChildren = 'draft_debug_relay_max_children';

  static int clampMaxDirectLinks(int value) =>
      value.clamp(minMaxDirectLinks, maxMaxDirectLinks);

  static int clampRelayMaxChildren(int value) =>
      value.clamp(minRelayMaxChildren, maxRelayMaxChildren);
}
