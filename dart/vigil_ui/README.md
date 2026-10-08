A Flutter inspector for calls captured by `vigil_core`. It provides request
search and filters, request/response details, cURL export, client and server
timing, complete lifecycle copy/share, request and response body copying, gated
debug details, and shake-to-open behavior.
The Debug tab also shows the captured client error, status, and response body
when an API fails without a `Vigil-Debug` header. A connection failure has no
server response, so server stack details cannot be displayed for that call.

## Installation

```sh
flutter pub add vigil_ui vigil_core
```

## Usage

Wrap the output of `MaterialApp.builder` so the inspector can cover every route:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vigil_ui/vigil_ui.dart';

MaterialApp(
  builder: (context, child) => VigilOverlay(
    enabled: kDebugMode,
    showFloatingButton: false,
    child: child ?? const SizedBox.shrink(),
  ),
  home: const HomePage(),
);
```

Shake is enabled by default. To use your own debug menu, present
`VigilInspector` directly. To offer a visible launcher during development, set
`showFloatingButton: true`.

```dart
const VigilInspector();
```

The overlay respects system insets for content while painting its background
edge-to-edge. Disable the overlay in production unless its captured data and
access model have been explicitly reviewed.
