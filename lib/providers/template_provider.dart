import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

/// A single captured DOM attribute (aria-label, role, text, data-testid, etc.)
/// used to uniquely identify a button in the Facebook UI.
class CapturedAttribute {
  final String key;
  final String value;

  const CapturedAttribute({required this.key, required this.value});

  factory CapturedAttribute.fromJson(Map<String, dynamic> j) =>
      CapturedAttribute(key: j['key'] as String, value: j['value'] as String);

  Map<String, dynamic> toJson() => {'key': key, 'value': value};
}

/// A single automation step: a human-readable label + the captured
/// multi-attribute fingerprint used to locate the DOM element at runtime.
class TemplateStep {
  final String label; // e.g. "Click Share button"
  final List<CapturedAttribute> attributes; // aria-label, role, text, testid…
  final String? fallbackText; // innerText fallback if attributes miss

  /// CSS selector string for the container scope in which to search for this
  /// step's element.  Set by Right-Click to Focus: the user right-clicks any
  /// element inside the desired container (e.g. a dialog) and the closest
  /// [role="dialog"] / [aria-modal] / [role="menu"] ancestor selector is stored
  /// here.  When non-null, _runStep / _buildStepJs will restrict the DOM search
  /// to document.querySelector(scopeSelector) instead of the full document.
  ///
  /// Null (default) = search the full document, preserving legacy behaviour.
  final String? scopeSelector;

  const TemplateStep({
    required this.label,
    required this.attributes,
    this.fallbackText,
    this.scopeSelector,
  });

  factory TemplateStep.fromJson(Map<String, dynamic> j) => TemplateStep(
        label: j['label'] as String,
        attributes: (j['attributes'] as List? ?? [])
            .map((e) => CapturedAttribute.fromJson(e as Map<String, dynamic>))
            .toList(),
        fallbackText: j['fallbackText'] as String?,
        scopeSelector: j['scopeSelector'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'attributes': attributes.map((a) => a.toJson()).toList(),
        if (fallbackText != null) 'fallbackText': fallbackText,
        if (scopeSelector != null) 'scopeSelector': scopeSelector,
      };

  /// Build a JS selector expression for this step's attributes.
  /// Priority order: aria-label → data-testid → role+text → text only.
  String toJsSelector() {
    final aria = _attrValue('aria-label');
    final testId = _attrValue('data-testid');
    final role = _attrValue('role');
    final text = fallbackText ?? _attrValue('text') ?? '';

    final parts = <String>[];

    if (aria != null) {
      final escaped = aria.replaceAll('"', '\\"');
      parts.add('[aria-label="$escaped"]');
    }
    if (testId != null) {
      parts.add('[data-testid="$testId"]');
    }
    if (role != null && text.isNotEmpty) {
      final escapedText = text
          .replaceAll("'", "\\'")
          .substring(0, text.length > 60 ? 60 : text.length);
      parts.add('[role="$role"]:contains-text("$escapedText")');
    }

    return parts.join(' | ');
  }

  TemplateStep copyWith({
    String? label,
    List<CapturedAttribute>? attributes,
    String? fallbackText,
    String? scopeSelector,
    bool clearScopeSelector = false,
  }) =>
      TemplateStep(
        label: label ?? this.label,
        attributes: attributes ?? this.attributes,
        fallbackText: fallbackText ?? this.fallbackText,
        scopeSelector:
            clearScopeSelector ? null : (scopeSelector ?? this.scopeSelector),
      );

  String? _attrValue(String key) {
    try {
      return attributes.firstWhere((a) => a.key == key).value;
    } catch (_) {
      return null;
    }
  }
}

/// A named automation template containing an ordered sequence of steps
/// plus shared configuration (post URL, delay, groups per run).
class AutomationTemplate {
  final String id; // UUID-like unique key
  String name; // User-facing label e.g. "Business Page Share"
  String description; // Optional notes
  String postUrl;
  int clickDelayMs;
  int groupsPerRun;
  List<TemplateStep> steps;
  DateTime createdAt;
  DateTime updatedAt;

  AutomationTemplate({
    required this.id,
    required this.name,
    this.description = '',
    this.postUrl = '',
    this.clickDelayMs = 600,
    this.groupsPerRun = 10,
    List<TemplateStep>? steps,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : steps = steps ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory AutomationTemplate.fromJson(Map<String, dynamic> j) =>
      AutomationTemplate(
        id: j['id'] as String,
        name: j['name'] as String,
        description: (j['description'] as String?) ?? '',
        postUrl: (j['postUrl'] as String?) ?? '',
        clickDelayMs: (j['clickDelayMs'] as int?) ?? 600,
        groupsPerRun: (j['groupsPerRun'] as int?) ?? 10,
        steps: (j['steps'] as List? ?? [])
            .map((e) => TemplateStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        updatedAt: j['updatedAt'] != null
            ? DateTime.tryParse(j['updatedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'postUrl': postUrl,
        'clickDelayMs': clickDelayMs,
        'groupsPerRun': groupsPerRun,
        'steps': steps.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  AutomationTemplate copyWith({
    String? name,
    String? description,
    String? postUrl,
    int? clickDelayMs,
    int? groupsPerRun,
    List<TemplateStep>? steps,
  }) =>
      AutomationTemplate(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        postUrl: postUrl ?? this.postUrl,
        clickDelayMs: clickDelayMs ?? this.clickDelayMs,
        groupsPerRun: groupsPerRun ?? this.groupsPerRun,
        steps: steps ?? this.steps,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}

// ─── Provider ─────────────────────────────────────────────────────────────────

class TemplateProvider extends ChangeNotifier {
  static const _templatesKey = 'fb_automation_templates';
  static const _activeKey = 'fb_active_template_id';

  List<AutomationTemplate> _templates = [];
  String? _activeTemplateId;
  bool _loaded = false;

  List<AutomationTemplate> get templates => List.unmodifiable(_templates);
  String? get activeTemplateId => _activeTemplateId;
  bool get loaded => _loaded;

  AutomationTemplate? get activeTemplate {
    if (_activeTemplateId == null) return null;
    try {
      return _templates.firstWhere((t) => t.id == _activeTemplateId);
    } catch (_) {
      return null;
    }
  }

  /// Display label shown in the debug/status bar. Req 5.
  String get activeLabel => activeTemplate != null
      ? '📋 Active Template: ${activeTemplate!.name}'
      : '';

  TemplateProvider() {
    _load();
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _activeTemplateId = prefs.getString(_activeKey);

    final raw = prefs.getString(_templatesKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _templates = list
            .map((e) => AutomationTemplate.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _templates = [];
      }
    }

    // Seed two default templates on first run
    if (_templates.isEmpty) {
      _templates = [
        AutomationTemplate(
          id: 'default_personal',
          name: 'Personal Profile Share',
          description: 'Standard share to groups from a personal profile post.',
          clickDelayMs: 2100,
          groupsPerRun: 10,
          steps: [
            const TemplateStep(
              label: 'Click Share button',
              attributes: [
                CapturedAttribute(
                  key: 'aria-label',
                  value: 'Send this to friends or post it on your profile.',
                ),
              ],
            ),
            const TemplateStep(
              label: 'Click Group option',
              attributes: [CapturedAttribute(key: 'role', value: 'button')],
              fallbackText: 'Group',
            ),
          ],
        ),
        AutomationTemplate(
          id: 'default_business',
          name: 'Business Page Share',
          description: 'Share from a Business/Fan Page — different UI layout.',
          clickDelayMs: 2500,
          groupsPerRun: 10,
          steps: [
            const TemplateStep(
              label: 'Click Share button (Page UI)',
              attributes: [
                CapturedAttribute(key: 'aria-label', value: 'Share'),
              ],
            ),
            const TemplateStep(
              label: 'Click Group option',
              attributes: [CapturedAttribute(key: 'role', value: 'button')],
              fallbackText: 'Group',
            ),
          ],
        ),
      ];
      await _persist();
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _templatesKey, jsonEncode(_templates.map((t) => t.toJson()).toList()));
    if (_activeTemplateId != null) {
      await prefs.setString(_activeKey, _activeTemplateId!);
    }
  }

  // ── CRUD ───────────────────────────────────────────────────────────────────

  Future<void> addTemplate(AutomationTemplate template) async {
    _templates.add(template);
    await _persist();
    notifyListeners();
  }

  Future<void> updateTemplate(AutomationTemplate updated) async {
    final idx = _templates.indexWhere((t) => t.id == updated.id);
    if (idx == -1) return;
    _templates[idx] = updated;
    await _persist();
    notifyListeners();
  }

  Future<void> deleteTemplate(String id) async {
    // Don't allow deleting default templates
    if (id == 'default_personal' || id == 'default_business') return;
    _templates.removeWhere((t) => t.id == id);
    if (_activeTemplateId == id) {
      _activeTemplateId = _templates.isNotEmpty ? _templates.first.id : null;
    }
    await _persist();
    notifyListeners();
  }

  // Callback set by home_screen / main to push steps into AutomationProvider
  // when the active template changes (Req 5 — immediate refresh on switch).
  void Function(AutomationTemplate)? onTemplateActivated;

  Future<void> setActiveTemplate(String? id) async {
    _activeTemplateId = id;
    final prefs = await SharedPreferences.getInstance();
    if (id != null) {
      await prefs.setString(_activeKey, id);
    } else {
      await prefs.remove(_activeKey);
    }
    // Req 5: push updated steps immediately so AutomationProvider refreshes
    if (id != null && onTemplateActivated != null) {
      final tpl = _templates.firstWhere(
        (t) => t.id == id,
        orElse: () => _templates.first,
      );
      onTemplateActivated!(tpl);
    }
    notifyListeners();
  }

  /// Duplicate an existing template under a new name.
  Future<AutomationTemplate> duplicateTemplate(
      String id, String newName) async {
    final src = _templates.firstWhere((t) => t.id == id);
    final copy = AutomationTemplate(
      id: 'tpl_${DateTime.now().millisecondsSinceEpoch}',
      name: newName,
      description: src.description,
      postUrl: src.postUrl,
      clickDelayMs: src.clickDelayMs,
      groupsPerRun: src.groupsPerRun,
      steps: src.steps
          .map((s) => TemplateStep(
                label: s.label,
                attributes: List.from(s.attributes),
                fallbackText: s.fallbackText,
              ))
          .toList(),
    );
    await addTemplate(copy);
    return copy;
  }

  /// Create a fresh blank template from the currently scanned element data.
  /// Call this after the user has used the Inspector to capture attributes.
  Future<AutomationTemplate> createFromCapture({
    required String name,
    required String postUrl,
    required int clickDelayMs,
    required int groupsPerRun,
    required List<TemplateStep> steps,
  }) async {
    final tpl = AutomationTemplate(
      id: 'tpl_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      postUrl: postUrl,
      clickDelayMs: clickDelayMs,
      groupsPerRun: groupsPerRun,
      steps: steps,
    );
    await addTemplate(tpl);
    await setActiveTemplate(tpl.id);
    return tpl;
  }

  /// Quick-update a step's captured attributes (used by Inspector capture flow).
  Future<void> updateStepAttributes(
    String templateId,
    int stepIndex,
    List<CapturedAttribute> attributes, {
    String? fallbackText,
    String? scopeSelector,
    bool clearScopeSelector = false,
  }) async {
    final tplIdx = _templates.indexWhere((t) => t.id == templateId);
    if (tplIdx == -1) return;
    final tpl = _templates[tplIdx];
    if (stepIndex >= tpl.steps.length) return;
    final oldStep = tpl.steps[stepIndex];
    final newSteps = List<TemplateStep>.from(tpl.steps);
    newSteps[stepIndex] = oldStep.copyWith(
      attributes: attributes,
      fallbackText: fallbackText ?? oldStep.fallbackText,
      scopeSelector: scopeSelector,
      clearScopeSelector: clearScopeSelector,
    );
    _templates[tplIdx] = tpl.copyWith(steps: newSteps);
    await _persist();
    notifyListeners();
  }
}

/// Generate a unique ID string.
String generateId() => 'tpl_${DateTime.now().millisecondsSinceEpoch}';
