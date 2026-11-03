# vigil_core

Core, platform-independent primitives for the Vigil network inspector. This
package owns captured-call models, privacy masking, W3C trace context,
`Server-Timing` parsing, debug payload parsing, and cURL export.

Most Flutter applications should install the umbrella `vigil` package instead.
The matching Node packages are
[`@vigiljs/core`](https://www.npmjs.com/package/@vigiljs/core) for protocol
helpers and [`@vigiljs/express`](https://www.npmjs.com/package/@vigiljs/express)
for server timing, gated error diagnostics, and optional ingest.

## Installation

```sh
dart pub add vigil_core
```

## Usage

```dart
import 'package:vigil_core/vigil_core.dart';

void main() {
  Vigil.instance.init(
    config: const VigilConfig(
      maxCalls: 200,
      maxBodyBytes: 32 * 1024,
      maskHeaders: {'authorization', 'cookie', 'set-cookie'},
      maskBodyFields: {'password', 'token', 'secret'},
    ),
  );

  final trace = VigilTraceContext.generate();
  print(trace.toHeader());

  final timings = VigilServerTimingParser.parse(
    'db;dur=24.5;desc="Load account", cache;dur=2.1',
  );
  print(timings.length);
}
```

Captured values are held in memory and exposed as immutable call-list views.
Bodies are capped by `maxBodyBytes`; common credential headers and body fields
are masked by default. Extend those sets for the vocabulary used by your API.
`VigilCurlExporter` turns a captured request into cURL so it can be reproduced
or shared with a backend teammate. The Flutter inspector in
[`vigil`](https://pub.dev/packages/vigil) adds one-tap Copy cURL and lifecycle
sharing. Review URLs and query parameters before sharing captured data.

See the [Vigil repository](https://github.com/guptan404/vigil) for architecture,
security guidance, and related packages.
