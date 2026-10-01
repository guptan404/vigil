# @vigil/core

Protocol helpers shared by Vigil Node integrations: W3C trace context,
`Server-Timing` serialization, recursive field masking, and size-limited gated
debug payload encoding.

## Installation

```sh
npm install @vigil/core
```

This package is ESM-only and requires Node.js 18 or newer.

## Usage

```ts
import {
  encodeDebugPayload,
  generateTraceparent,
  parseTraceparent,
  serializeServerTiming,
} from "@vigil/core";

const traceparent = generateTraceparent();
const parsed = parseTraceparent(traceparent);

const serverTiming = serializeServerTiming([
  { name: "db", duration: 24.5, description: "Load account" },
]);

const debug = encodeDebugPayload(
  { error: "Example failure", context: { token: "secret" } },
  { maskFields: ["token"] },
);
```

`encodeDebugPayload` returns base64url-encoded JSON intended for the
`Vigil-Debug` response header. It masks configured field names recursively and
truncates large payloads to stay under the configured header limit.

See [`@vigil/express`](https://www.npmjs.com/package/@vigil/express) for the
ready-to-use Express integration.
