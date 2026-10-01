# Contributing

Thanks for helping improve Vigil.

## Development setup

Install Dart 3.9 or newer, Flutter 3.27 or newer, and Node.js 22.12 or newer.
Then bootstrap both workspaces:

```sh
dart pub get
dart run melos bootstrap
npm ci
```

## Before opening a pull request

Run the same checks used for release preparation:

```sh
dart run melos run format
dart run melos run analyze
dart run melos run test
npm run check
```

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
