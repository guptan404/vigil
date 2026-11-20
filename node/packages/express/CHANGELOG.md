# Changelog

## Unreleased

- Automatically select the captured request's HTTP method in desktop response controls, including separate choices for methods sharing one path.
- Added request-linked log diagnostics and registered code failure points.
- Added device-session capture ingestion and a keyed desktop inspector with direct session connection.
- Added session-scoped response mocks, exceptions, delays, timeouts, and disconnects, with separate read/control keys and captured-path eligibility.
- Refined Vigil desktop branding and independent request/detail scrolling; documented complete setup and deployment.

## 0.1.2

- Use the updated debug encoder to preserve redaction and enforce size limits in response headers.

## 0.1.1

- Added gated `Vigil-Debug` diagnostics for direct 4xx and 5xx responses.
- Preserved richer diagnostics from `vigilErrorHandler` when a request reaches it.

## 0.1.0

- Added Express request timing and trace correlation middleware.
- Added gated error diagnostics with optional error pass-through.
- Added keyed client-call ingestion and a bounded in-memory sink.
