# Global rules index

Human-readable catalog of the global ("constitution") rules in this repository.
Every rule below is an [OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
`Rule` unit with octospec extension fields for on-demand injection.

For machine-precise injection metadata, see each rule's frontmatter.

## Rules

- [Security red lines](security.md) — non-negotiable security rules; any violation is a P0 blocker. *(load-bearing, priority 95)*
- [Comprehension gate](comprehension-gate.md) — load-bearing or architectural changes require demonstrated understanding before merge. *(load-bearing, priority 90)*
- [Code review standards](review.md) — standards reviewers (human or AI) must apply before approving. *(priority 78)*
- [Pull request conventions](pr.md) — how pull requests must be structured, described, and linked. *(priority 75)*
- [Commit conventions](commit.md) — use Conventional Commits for all commit messages. *(priority 70)*

## How these are consumed

- **Claude Code / agents** read frontmatter `inject_when` to decide which rules
  apply to the files being changed, and inject them on demand.
- **Per-repo `.octospec/`** inherits this layer via a pinned version in its
  `manifest.yaml` (`inherits: octo-spec@<semver>`), synced with
  `scripts/octospec-sync.sh`.
- **Any OKF-aware tool** can read this directory as a valid OKF knowledge bundle.
