## Unreleased

- Match the inspector and system navigation area to the app's scaffold background, avoiding a tinted bottom strip.
- Handle system Back inside the inspector before closing it, preserving the underlying app route, including MaterialApp.router integrations.
- Added expandable JSON search and JSON-path copying, host/method/status/duration filters, saved sessions with notes and import/export, and request/response comparison.
- Added edit/replay and local mock editors, session-ID copying, and refined Vigil branding.
- Added separate copy actions for the endpoint, request content, and response content, plus a **Copy all** action that copies them together, configurable with `VigilCopyOptions`.
- Copied JSON bodies and session JSON are now pretty-printed so formatting survives pasting into notes and editors.
- The request details header collapses to icon-only actions while scrolling, with an expand button to restore it.
- The request list now always shows when each call was triggered, including on phone-width screens.

## 0.1.2

- Update the capture dependency and document cURL and lifecycle sharing.

## 0.1.1

- Added copy and platform-share actions for the complete request lifecycle.
- Added dedicated copy actions for captured request and response bodies.
- Show captured client failure details in the Debug tab when no gated server payload is present.

## 0.1.0

- Added a searchable, filterable Flutter network inspector.
- Added request, response, timing, debug, and cURL views.
- Added shake and optional floating-button launch behavior.
