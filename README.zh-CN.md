# octo-spec

[English](README.md) | [简体中文](README.zh-CN.md)

[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![OKF conformance](https://github.com/Mininglamp-OSS/octo-spec/actions/workflows/octospec-lint.yml/badge.svg)](https://github.com/Mininglamp-OSS/octo-spec/actions/workflows/octospec-lint.yml)
[![Version](https://img.shields.io/github/v/tag/Mininglamp-OSS/octo-spec?label=version&sort=semver)](https://github.com/Mininglamp-OSS/octo-spec/tags)

**面向 AI 辅助编码的开箱即用工程规范** —— **git 原生、零服务**,以**开放格式(OKF)** 存储,采用**两层 constitution**(组织级 `_global` 规则 + 仓库本地规则)。

**没有 octo-spec:** 每开一个新的 AI 会话,你都要把约定重讲一遍 —— 提交规范、
错误处理、这次改动碰了哪些规则 —— agent 照样跑偏。

**有了 octo-spec:** 规范就在仓库里。`git pull` 带过来,任何编码 agent 自动读取并
遵守 —— 不用重讲。

```mermaid
flowchart TD
    subgraph SOT["Source of truth (in the repo)"]
        R[".octospec/rules/<br/>team conventions"]
        G[".octospec/_global/<br/>org-wide rules (synced, git-ignored)"]
    end

    subgraph Pointers["Entry-point pointers (just signposts)"]
        C["CLAUDE.md"]
        A["AGENTS.md"]
        CMD[".claude/commands/<br/>slash commands"]
    end

    subgraph Agents["Whoever does the work"]
        CC["Claude Code"]
        CX["Codex"]
        OC["OpenClaw"]
    end

    R --> C & A
    G --> R
    C --> CC
    CMD --> CC
    A --> CX
    A --> OC
    OC -.spawns.-> CC
    OC -.spawns.-> CX

    CC & CX & OC --> OUT["Code that follows<br/>the same rules"]
```

**一个真相源(`.octospec/`),多个入口点。**

AI 写代码很快,但每次会话都从零开始 —— 它记不住你的项目、你的约定,也记不住团队的需求。octo-spec
把规格(spec)、任务(task)和项目记忆 **持久化到你的仓库里**,这样任何编码 agent 都能按照你
团队的工程规范来工作。

octo-spec 是 **git 原生(git-native)** 且 **Claude Code 优先(Claude Code first)** 的:没有
需要运行的中心服务器,也没有需要额外安装的服务。克隆仓库,共享规范就一起带过来了 —— 可评审、
可版本化,像任何其他代码产物一样可持续改进。

## 前置依赖(Prerequisites)

- **git** —— octo-spec 是 git 原生的;规范随仓库一起流转。
- **bash** —— 用于运行 `octospec-sync.sh`(接入)以及各助手脚本。
- **python3 + PyYAML** —— 仅在运行 OKF lint(`octospec-lint.sh`)时需要,
  用 `pip install pyyaml` 安装。
- 一个**编码 agent**(Claude Code、Codex、OpenClaw 等)来执行工作流。
  octo-spec 提供规则和脚本,真正写代码的是 agent。

## 快速开始

**最快路径(零 shell):把下面这句话粘给你的编码 agent**(Claude Code / Codex / OpenClaw):

> 读取 https://raw.githubusercontent.com/Mininglamp-OSS/octo-spec/v1.2.0/BOOTSTRAP.md 并按它把 octo-spec 接入这个仓库。

它会克隆钉死版本的 octo-spec,再帮你跑标准的 octospec-init 接入。下面的手动步骤仍是 source of truth。

> 用 Claude Code? **octospec-init** skill 会带 agent 走完这套接入(拷贝 → 确认 pin → sync → 校验)。下面是同一件事的手动版,仍是 source of truth。

```bash
# 1. 初始化 .octospec/ 骨架(模板自带 sync 脚本)
cp -r <path-to>/octo-spec/templates/octospec-init .octospec

# 2. 确认 .octospec/manifest.yaml 里的版本 pin。模板出厂即已 pin 到当前版本,
#    因此「同版接入」无需手改。然后把 GLOBAL_SRC 指向**同一版本**的 octo-spec
#    checkout —— pin 必须与该 checkout 的 VERSION 文件一致,否则 sync 直接 fail-fast。
export GLOBAL_SRC=/path/to/octo-spec

# 3. Sync。它会把全局规则 vendor 进 .octospec/_global/,把 octospec 块写进
#    CLAUDE.md / AGENTS.md,并把工具期望落在仓库根的脚手架「物化」出来:
#    slash 命令 + workflow skill 落到 .claude/,PR 模板落到 .github/。
#    开箱即用,且幂等。
./.octospec/scripts/octospec-sync.sh

# 4. 自检:跑 OKF lint(lint 脚本不 vendor,从 checkout 跑)
"$GLOBAL_SRC/scripts/octospec-lint.sh" .
```

到这里,**接入就完成了**。仓库现在带上了规则、agent 指令块、slash 命令(落在仓库根
`.claude/`,这样 Claude Code 才能发现)、以及 PR 模板(落在 `.github/`)。把新增文件
提交(`.octospec/`、根 `.claude/`、`.github/`,以及被更新的 `CLAUDE.md` / `AGENTS.md`);
此后每个同事只要 `git pull`。

**接下来 loop 怎么触发:** 跟你的编码 agent 说「加个功能」/「修这个 bug」,或者用 slash
命令显式驱动单个阶段(`/octospec-plan`、`/octospec-go`、`/octospec-check`、
`/octospec-finish`)。4 阶段循环由 **agent** 执行 —— 没有可粘贴的 loop CLI(见下方
[4 阶段循环](#4-阶段循环))。

关于 Claude Code 的 slash 命令工作流,见 [`docs/CLAUDE-WORKFLOW.md`](docs/CLAUDE-WORKFLOW.md)。

## 核心理念

| 能力 | 它带来的改变 |
|---|---|
| **规则自动注入** | 在 `.octospec/rules/` 里把约定写一次,然后让相关上下文被注入到每次 AI 会话中,而不必反复重复你自己。 |
| **以任务为中心的工作流** | 把任务简报(brief)、实现上下文和状态都放在 `.octospec/tasks/` 里,让 AI 的工作保持结构化。 |
| **项目记忆** | `.octospec/journal/` 中的共享日志保留了上一次发生过什么,这样每个新会话都能带着真实上下文起步。 |
| **团队共享标准** | 规格存在仓库里,因此某个人来之不易的一条规则能惠及整个团队。 |

## 4 阶段循环

```mermaid
flowchart LR
    P["规划"] --> I["实现"] --> V["验证"] --> F["收尾"]
    F -.提炼学习成果.-> P
```

```
Plan      → 写一份简报;AI 可以从现有代码起草,由你确认
Implement → AI 在相关规则自动注入的情况下写代码(不提交)
Verify    → 对照规则 + lint/类型检查/测试来校验 diff,并自我修复
Finish    → 运行一次最终检查,然后把新的学习成果于同一 PR 内提炼回 rules/
            (无死信;pending/ 只留未决项)
```

> **这个 loop 由你的编码 agent 执行,不是一组可粘贴的 CLI 命令。** 由 Claude Code 的
> slash 命令或 `octospec-workflow` skill 驱动 agent 走完这几个阶段。**octo-spec 本身
> 不含运行时引擎**:它的脚本只做 **sync**(接入 / vendor 全局规则 + 物化根脚手架)、
> **lint**(OKF 一致性)、以及收尾阶段的 **learning-reflow**(`octospec-update-spec.sh`)。
> 每个阶段所需的推理由 agent 负责。

## 两层模型

octo-spec 被拆分为两层,从而让共享标准与各仓库的具体细节互不冲突:

- **全局("宪法")** —— 即本仓库。每个项目都应遵循的跨仓库约定:提交规范、PR 规则、review
  标准、安全红线、理解力门禁(comprehension gate)。
- **每仓库("地方法")** —— 位于各业务仓库内部的一个 `.octospec/` 目录。仓库专属的规则,通过
  一个被钉住的版本(pinned version)继承自全局层。

## 构建于一种开放格式之上(OKF)

octo-spec 把它的规则、任务和日志(journal)存储为带 YAML frontmatter 的纯 Markdown,兼容
[Open Knowledge Format (OKF)](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
v0.1 —— 一种来自 Google Cloud Knowledge Catalog、采用 Apache-2.0 许可的开放知识格式。

这是一个有意为之的选择:知识最好用通用易得、广泛确立的格式来表示 —— 无需工具人类即可阅读、
无需专用 SDK agent 即可解析、在版本控制中可 diff、并且可在工具与组织之间移植。通过对齐 OKF,
一个 `.octospec/` 目录就是一个有效的 OKF 知识包(knowledge bundle)—— 任何支持 OKF 的工具或
agent 都能读取它 —— 同时 octospec 在其之上,作为 OKF 允许的扩展字段(extension fields),叠加了
自己的工作流层(按需注入规则、4 阶段循环以及 review 门禁)。

## 目录布局(每仓库的 `.octospec/`)

```
.octospec/
  manifest.yaml          # 继承的全局版本(已钉住)、仓库层级(tier)、负责人
  rules/                 # 规则的唯一真相来源(按需注入)
    <domain>.md
    _index.yaml          # 规则清单 + 注入触发条件 + 优先级
  tasks/<slug>/
    brief.md             # 目标 / 背景 / 关键承重清单(load-bearing list) / 验收
    context.yaml         # 已注入的规则 id + 注入指纹(fingerprint)
  journal/shared/<slug>.md      # 团队可见的结构性学习成果
  journal/by-actor/<actor>/<slug>.md  # 单个 actor 的任务级笔记(仓内)
  learnings/pending/<slug>.md   # 仅存放尚需人工设计的未决学习项
  scripts/
    octospec-update-spec.sh     # 收尾阶段助手:生成 rule 草稿 + promotion issue
                                # 正文,或写入 per-actor journal 条目
```

> 可复用的学习成果在收尾(Finish)阶段**于同一个 PR 内**就地回流(直接编辑相关的
> `rules/<rule>.md`,或新增一条 rule + `_index.yaml` 条目)——PR 评审即闸门。
> `learnings/pending/` 仅保留**尚未决、需要人工设计**才能成为规则的学习项;已完成的
> 学习成果绝不会滞留等待另一个 PR。`.octospec/scripts/octospec-update-spec.sh`
> 助手负责生成这些草稿素材,绝不直接写入 main 的 `rules/`。

## OKF 一致性(conformance)

知识文件(全局规则文件、任何仓库的 `rules/*.md`,以及每任务的 `tasks/**` 简报 / `journal/**`
条目)都是有效的 OKF 单元:每个文件都以一个正确终止的 YAML frontmatter 块开头,该块能解析为
有效 YAML 并声明一个非空的 `type`。结构性文件 `index.md` 和 `log.md` 被有意豁免(OKF 的
index/log 是没有 frontmatter 的纯 markdown),需填空的 `*.template.md` 脚手架同样豁免。CI 通过
`scripts/octospec-lint.sh`(一个 YAML 感知的 linter;需要 `python3` + PyYAML)来强制执行这一点,
因此格式永远不会漂移。在本地运行:

```bash
./scripts/octospec-lint.sh .
```

> 在被接入的业务仓里,lint 覆盖你自己的 `rules/` 和 `tasks/**`。vendor 进来的
> `.octospec/_global/` 是「在本仓 CI 里已经过 lint 的规则」的只读缓存,因此按设计**不在
> 被接入仓的 lint 范围内**。

一份人类可读的规则目录位于 [`global/index.md`](global/index.md),变更历史位于
[`global/log.md`](global/log.md)。

## 资源(Resources)

| 文档 | 内容 |
|---|---|
| [快速开始](#快速开始) | 四条命令接入一个仓库(拷贝 → pin → sync → lint)。 |
| [快速上手](docs/GETTING-STARTED.md) | 5 分钟指南 + 用法示例 + 图示。 |
| [集成架构](docs/INTEGRATION.md) | 每个入口点(Claude Code、Codex、Octo bots、派单)如何接入该标准。 |
| [Claude Code 工作流](docs/CLAUDE-WORKFLOW.md) | slash 命令 + 零安装 / 物化模型。 |
| [变更历史](global/log.md) | 全局规则变更的带日期日志。 |

## 常见问题(FAQ)

<details>
<summary><strong>需要安装什么吗?</strong></summary>

没有需要运行的服务。维护者把仓库接入并提交结果之后,每个同事只要 `git pull` —— 规则、
agent 块、slash 命令、PR 模板都随仓库带过来。要运行 OKF lint 则需要 `python3` + PyYAML
(见[前置依赖](#前置依赖prerequisites))。
</details>

<details>
<summary><strong>octo-spec 会替我跑编码 loop 吗?</strong></summary>

不会。octo-spec 提供规则和三个脚本(sync / lint / learning-reflow)。
Plan→Implement→Verify→Finish 这个 loop 由你的**编码 agent** 执行(经由 Claude Code 的
slash 命令或 `octospec-workflow` skill)。没有运行时引擎,也没有可粘贴的 loop CLI。
</details>

<details>
<summary><strong>如果我不用它会怎样?</strong></summary>

对你毫无影响。`.octospec/` 是叠加式的 —— 它只新增文件,不碰任何运行时代码,也不拦截任何
merge。删掉 `.octospec/` 即可完全回滚。
</details>

<details>
<summary><strong>规则从哪来?</strong></summary>

来自本仓库现有的约定,被原子化、可校验化。通过对 `.octospec/rules/` 发普通 PR 来提议新规则。
把一条学习成果提炼成规则,就是一次常规的、经过评审的 PR —— 标准就是这样越来越聪明,而不会
悄悄漂移。
</details>

<details>
<summary><strong>为什么 sync 在 <code>.octospec/</code> 之外也写了文件?</strong></summary>

这是有意为之。Claude Code 只在仓库根 `.claude/` 发现 slash 命令 / skill,GitHub 也只在
仓库根 `.github/` 套用 PR 模板。所以 sync 把这些从 `.octospec/` 物化到根目录 ——
install-if-missing(绝不覆盖你已自定义的文件),且重跑幂等。
</details>

## 许可证

octo-spec 采用 **Apache License 2.0** 许可。见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。

## 说明(Notes)

<details>
<summary>sync 机制与注意事项</summary>

- 模板自带它自己的 `scripts/`(`octospec-sync.sh` + `octospec_sync_block.py`),所以被复制出来的 `.octospec/` 自身就带着这些 sync 脚本 —— 你不需要为了定位脚本而保留一条回到 octo-spec checkout 的路径。全局规则在 sync 时仍然来源于一个 octo-spec checkout(见 `GLOBAL_SRC`)。
- sync 会把全局规则 vendor 进被 git 忽略的 `.octospec/_global/`,并且把 octospec 的 agent 指令块写入你的 agent 文件(`CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / `QWEN.md`),写在受管标记(managed markers)之间。
- sync 还会**物化仓库根脚手架**(工具只在仓库根才能发现的那部分):把 `.octospec/.claude/`(slash 命令 + skill)复制到仓库根 `.claude/`,把 `.octospec/.github/PULL_REQUEST_TEMPLATE.md` 复制到 `.github/`。这是 install-if-missing —— 目标位置已存在的文件保持不动,因此手写的自定义内容绝不会被覆盖。
- 每次你 bump 这个 pin 时都可以重新运行;它是幂等的,并且会保留标记之外的任何内容 —— 包括文件原有的行尾(LF/CRLF)和末尾换行符。第二次运行会报告根脚手架已存在。
- vendor 进 `.octospec/scripts/` 的脚本是本仓库中规范来源 `scripts/octospec-sync.sh` 和 `scripts/octospec_sync_block.py` 的逐字节副本;CI(`scripts/test_octospec_sync_sh.sh`)会断言它们保持完全一致,因此副本绝不会悄悄偏离被测试过的源。要升级工具本身,就从一个更新的 octo-spec checkout 重新复制模板的 `scripts/`(或仅复制这两个文件)。

</details>
