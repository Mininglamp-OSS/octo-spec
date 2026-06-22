# octo-spec bootstrap (one-liner onboarding)

> ⚠️ 知情提示 / Heads-up: 按本文件操作会让你的 agent **`git clone` octo-spec 仓库到一个临时目录**，
> 并在**当前仓库**运行其 sync 脚本（写入 `.octospec/` 与 agent 指令块）。这是远程文档驱动的本地执行；
> 版本已钉死在 `v1.2.0`（可复现、可审计）。不接受请勿继续。
> Following this file makes your agent clone the octo-spec repo to a temp dir and run its
> sync script against THE CURRENT repo. Version is pinned to `v1.2.0`. Stop here if that's not intended.

## 你（agent）要做的 / What the agent should do

1. 把 octo-spec 浅克隆到临时目录（版本钉死，**勿改 tag**）:
   ```bash
   OCTOSPEC_SRC="$(mktemp -d)/octo-spec"
   git clone --depth 1 --branch v1.2.0 https://github.com/Mininglamp-OSS/octo-spec "$OCTOSPEC_SRC"
   ```
2. 打开 `"$OCTOSPEC_SRC/templates/octospec-init/.claude/skills/octospec-init/SKILL.md"`，
   **照其 5 步在当前仓库执行**（copy → pin → sync → verify → lint），其中：
   - 第 1 步的 `<path-to>/octo-spec` = `"$OCTOSPEC_SRC"`
   - 第 2 步 manifest 钉 `inherits: octo-spec@1.2.0`
   - 第 3、5 步 `GLOBAL_SRC="$OCTOSPEC_SRC"`
3. 完成后可删临时目录 `rm -rf "$OCTOSPEC_SRC"`。

> 单一事实源仍是 octospec-init skill；本文件只补「用户本地没有 octo-spec checkout」这一步。
