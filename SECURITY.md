# Security policy

## Supported versions

Vigil is currently in initial development. Security fixes are applied to the
latest `0.1.x` release only.

## Reporting a vulnerability

Do not include a vulnerability, production endpoint, credential, token, request
body, stack trace, or customer data in a public issue. Use GitHub's private
security advisory flow for this repository:

1. Open the repository's **Security** tab.
2. Choose **Advisories** and **Report a vulnerability**.
3. Include a minimal reproduction using synthetic data.

If private vulnerability reporting is not enabled, open a public issue asking
the maintainer to enable it without disclosing technical details.

## Deployment guidance

Vigil captures HTTP metadata and optional bodies. Keep capture, ingest, and
debug diagnostics disabled in production by default. Use TLS, restrictive CORS,
rate limits, short retention, and application-specific masking whenever captured
data leaves the device.
