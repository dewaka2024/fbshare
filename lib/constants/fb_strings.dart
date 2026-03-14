// ─── Multilingual constants used in both Dart and injected JS ─────────────────
// All share/group related UI strings in one place.
// When adding a new language, add entries here ONLY — not in individual files.

class FbStrings {
  // ── Share button labels ──────────────────────────────────────────────────
  static const shareExact = [
    'share',
    'Share',
    'SHARE',
    'බෙදාගන්න', // Sinhala
    'බෙදා ගන්න', // Sinhala (spaced variant)
    'partager', // French
    'teilen', // German
  ];

  // ── "Share to Group" menu option labels ─────────────────────────────────
  static const shareToGroupExact = [
    'Group',
    'Groups',
    'share to group',
    'share to a group',
    'share to groups',
    'share to your group',
    'post to groups',
    'සමූහය', // Sinhala
    'සමූහ',
    'කණ්ඩාය',
    'කණ්ඩායමට',
    'කණ්ඩායමකට',
  ];

  // ── Post / submit button labels ──────────────────────────────────────────
  // IMPORTANT: 'share' and 'Share' are intentionally NOT listed here.
  // Facebook's composer dialog contains audience-selector and share-option
  // buttons also labelled "Share" — clicking those closes the composer and
  // triggers the "Leave page?" modal instead of submitting the post.
  // Only include labels that exclusively identify the SUBMIT / POST action.
  static const postExact = [
    'post',
    'Post',
    'share now', // "Share now" = safe, only used on the submit button
    'Share now',
    'පළ කරන්න', // Sinhala: "Publish / Post"
  ];

  // ── Labels that should NEVER match as share buttons ──────────────────────
  static const excluded = [
    'leave a comment',
    'comment',
    'like',
    'react',
    'send',
    'bookmark',
    'save',
    'follow',
    'unfollow',
    'more',
    'hide',
    'report',
  ];

  // ── isShareRelated extra keywords (for PageElement filter) ───────────────
  static const shareKeywords = [
    'share',
    'group',
    'බෙදා',
    'කණ්ඩා',
    'partager',
    'teilen',
  ];

  static const shareExcludeKeywords = [
    'comment',
    'like',
    'react',
    'emoji',
    'sticker',
    'gif',
    'photo',
    'avatar',
  ];

  // ── JS-embeddable string lists (used inside _coreScript) ─────────────────
  // Returns a JS array literal string, e.g. "['share','Share',...]"
  static String toJsArray(List<String> items) {
    final escaped = items.map((s) => "'${s.replaceAll("'", "\\'")}'").join(',');
    return '[$escaped]';
  }
}
