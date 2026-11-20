# Contributing

Thanks for helping improve Vigil.

## Development setup

Install a Flutter SDK containing Dart 3.9+, and Node.js 22.12+ within 22.x or
Node.js 24+. Then resolve both workspaces:

```sh
dart pub get
npm ci
```

## Before opening a pull request

Run the same checks used for release preparation:

```sh
./tool/release_check.sh
```

This runs formatting, analysis, all Dart/Flutter and Node tests, protocol
integration, documentation generation, and package dry runs. It uses Pub's
workspace resolution directly and does not require a global Melos installation.

Add tests for behavior changes and update the relevant package changelog when a
consumer-visible API or behavior changes. Never commit real request payloads,
credentials, ingest keys, debug keys, tokens, or customer data.

## Design principles

- Capture must remain bounded in memory and body size.
- Sensitive headers and fields must be masked before data is retained.
- Backend diagnostics must remain opt-in and gated.
- Integrations should preserve the host application's response and error flow.
- Published packages should keep their dependency surface small.

## Reporting issues

Use the [GitHub issue tracker](https://github.com/guptan404/vigil/issues) for
ordinary bugs and feature requests. Follow `SECURITY.md` for vulnerabilities or
reports that might expose private data.
