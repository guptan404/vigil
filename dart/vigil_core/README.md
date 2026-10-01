Core, platform-independent primitives for the Vigil network inspector. This
package owns captured-call models, privacy masking, W3C trace context,
`Server-Timing` parsing, debug payload parsing, and cURL export.

Most Flutter applications should install the umbrella `vigil` package instead.

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

See the [Vigil repository](https://github.com/guptan404/vigil) for architecture,
security guidance, and related packages.
