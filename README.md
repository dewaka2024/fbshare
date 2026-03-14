# FB Share Automation — Flutter Windows Desktop App

Facebook posts automatically groups walata share karanna Windows desktop app ekak.

## Features
- WebView2 (webview_windows) eken embedded Facebook browser
- MutationObserver state machine — 4-step automation (Share → Group → Select Group → Post)
- Template system — different FB profiles/pages walata different automation configs
- Page Inspector — elements scan karala aria-labels copy karanna
- Run history — last 50 runs persist karanawa
- Light/Dark mode

## Setup

```bash
flutter pub get
flutter run -d windows
```

## Assets
- `assets/scripts/fb_share_automation.js` — New MutationObserver state machine (Req 1–6)
- `assets/scripts/deep_scan.js` — Page Inspector element scanner

## JS Integration (FbAutomationInjector)

```dart
import 'lib/services/fb_automation_injector.dart';

final injector = FbAutomationInjector(
  controller: _webviewController,
  messageStream: _webMessageBroadcast,
);

final result = await injector.shareToGroup(
  groupName: 'My Facebook Group',
  clickDelayMs: 1500,
);

if (result['success'] == true) {
  print('Posted to: ${result['groupName']}');
} else {
  print('Error at step: ${result['step']} — ${result['error']}');
}
```

## Requirements (Windows)
- Flutter 3.10+
- Windows 10/11 with WebView2 Runtime installed
- Facebook account (stays logged in via persistent WebView2 profile)
