# Changelog

## 0.1.1

- Added gated `Vigil-Debug` diagnostics for direct 4xx and 5xx responses.
- Preserved richer diagnostics from `vigilErrorHandler` when a request reaches it.

## 0.1.0

- Added Express request timing and trace correlation middleware.
- Added gated error diagnostics with optional error pass-through.
- Added keyed client-call ingestion and a bounded in-memory sink.
