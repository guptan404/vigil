## 0.1.2

- Wait for in-flight uploads during disposal and keep the connection closed to new events during the final flush.
- Preserve newer queued calls when older entries are evicted during an upload.

## 0.1.1

- Updated the `vigil_core` dependency for the coordinated patch release.

## 0.1.0

- Added bounded batching and retry-on-next-flush behavior for captured calls.
- Added configurable ingest headers, timeouts, client metadata, and queue limits.
