# Contributing

Contributions are welcome through focused issues and pull requests.

## Checks

Run these commands before submitting a change:

```bash
moon fmt --check
moon check --deny-warn
moon check --target js --deny-warn
moon build
moon test
```

Changes to generated source must include focused unit tests. If a change affects
syntax or project layout, add or update an example that CI generates and checks
as an independent MoonBit project.

Keep commits scoped to one behavior. Do not commit `_build`, credentials, local
registry caches, or generated consumer directories.
