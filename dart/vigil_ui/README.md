# vigil_ui

A Flutter inspector for calls captured by `vigil_core`. It provides request
search and filters, request/response details, one-tap Copy cURL, client and
server timing, lifecycle JSON copy/share, body copying, gated debug details,
and shake-to-open behavior. Copy cURL helps a backend teammate replay a
request after replacing redacted credentials; lifecycle JSON includes its
trace, request, response, timings, and failure details for handoff.

The Debug tab also shows the captured client error, status, and response body
when an API fails without a `Vigil-Debug` header. A connection failure has no
server response, so server stack details cannot be displayed for that call.

With [`@vigiljs/express` on npm](https://www.npmjs.com/package/@vigiljs/express)
and a matching debug key, it can show the backend error message, stack, and
request context for that response. It does not fetch a server log stream.

Most Flutter apps can install [`vigil`](https://pub.dev/packages/vigil), which
includes this UI, Dio capture, and optional upload.

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
Review cURL and lifecycle JSON before sharing: configured headers and JSON
body fields are masked, but URLs can contain sensitive query parameters.
