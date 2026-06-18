---
id: commit
tier: global
priority: 70
load_bearing: false
inject_when:
  paths: ["**"]
  touches: ["commit", "git"]
source: self
supersedes: []
---

# Commit conventions

Use [Conventional Commits](https://www.conventionalcommits.org/).

```
<type>(<scope>): <subject>

<body>

<footer>
```

## Types

| Type | Use for |
|---|---|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `test` | Adding or fixing tests |
| `chore` | Build process, tooling, dependencies |
| `perf` | A performance improvement |

## Rules

- Subject line: imperative mood, ≤ 72 chars, no trailing period.
- One logical change per commit. Do not mix refactor + feature.
- Reference the issue in the footer: `Fixes #123` / `Refs #123`.
- The commit author must be the real human or agent that did the work; do not
  impersonate another author.
- Do not commit secrets, credentials, tokens, or private endpoints. Ever.
