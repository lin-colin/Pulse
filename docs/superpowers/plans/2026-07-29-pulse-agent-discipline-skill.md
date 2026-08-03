# Pulse Agent Discipline Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a portable Antigravity skill that enforces disciplined requirement analysis, testing, review, verification and truthful handoff for Pulse work.

**Architecture:** Keep behavior and domain knowledge separate. `pulse-disciplined-engineering` defines mandatory engineering gates and reusable response templates; the existing `pulse-hardware-monitoring` skill remains the source of Pulse metric truth. The remaining Task 3 file is updated to load both layers before review.

**Tech Stack:** Markdown, YAML frontmatter, existing `skill-creator` validation script.

**Constraint:** User explicitly prohibits Git commits. Do not create commits or alter Pulse product code.

---

## File map

- Create `antigravity/skills/pulse-disciplined-engineering/SKILL.md`: high-constraint behavior skill.
- Create `antigravity/skills/pulse-disciplined-engineering/references/pulse-workflow-template.md`: copyable templates for analysis, decision, test plan, review and handoff.
- Modify `antigravity/tasks/task-03-a1-ui-quality-review.md`: require both skills and make the quality gate explicit.
- Optional generated metadata `antigravity/skills/pulse-disciplined-engineering/agents/openai.yaml`: harmless for Antigravity and useful to other compatible consumers.

### Task 1: Create the behavior skill and templates

**Files:**

- Create: `antigravity/skills/pulse-disciplined-engineering/SKILL.md`
- Create: `antigravity/skills/pulse-disciplined-engineering/references/pulse-workflow-template.md`
- Create: `antigravity/skills/pulse-disciplined-engineering/agents/openai.yaml`

- [ ] **Step 1: Initialize a valid skill directory**

Run:

```bash
python3 /Users/hlc/.codex/skills/.system/skill-creator/scripts/init_skill.py \
  pulse-disciplined-engineering \
  --path /Users/hlc/Documents/PulseProject/antigravity/skills \
  --resources references \
  --interface 'display_name=Pulse Disciplined Engineering' \
  --interface 'short_description=Force evidence-driven engineering before code changes.' \
  --interface 'default_prompt=Use this skill to handle a Pulse task with analysis, tests, review, and verified delivery.'
```

Expected: a directory containing `SKILL.md`, `agents/openai.yaml`, and `references/`.

- [ ] **Step 2: Replace the template with mandatory behavioral gates**

Write frontmatter exactly with `name: pulse-disciplined-engineering` and a description that triggers on Pulse implementation, diagnosis, review, verification and bug-fix requests.

The body must require this sequence:

```text
classify request → restate goal/non-goal/success → distinguish fact/assumption/unknown
→ read-only evidence or one blocking question → impact analysis → options and approval
→ failure evidence/test design → minimal scoped change → verification → two-stage review → handoff
```

Include explicit prohibitions: no immediate coding, no fabricated results, no treating compilation as completion, no broad refactor, no Git commit, no external data mutation, no hiding unavailable data as zero.

Include explicit stop conditions: missing decision, missing authority, conflicting user changes, unverified critical source, failed validation, or destructive/external action.

- [ ] **Step 3: Add a copyable workflow reference**

Create `references/pulse-workflow-template.md` with these exact sections:

```markdown
## 需求记录
目标：
非目标：
成功标准：
事实：
假设：
未知项：

## 影响分析
数据流：
受影响文件与调用方：
回归风险：

## 验证计划
失败前证据：
单元/集成/实机验证：
预期结果：

## 审查清单
需求完整性：
边界与错误处理：
并发与生命周期：
范围漂移：

## 最终交付
改动：
证据：
验证：
限制：
未做事项：
Git：未提交/已按授权操作
```

Each section must instruct the agent to fill it with concise evidence, not boilerplate.

- [ ] **Step 4: Manually verify the skill structure before integration**

Run:

```bash
sed -n '1,24p' antigravity/skills/pulse-disciplined-engineering/SKILL.md
find antigravity/skills/pulse-disciplined-engineering -maxdepth 3 -type f | sort
rg -n '\[TODO|TODO:' antigravity/skills/pulse-disciplined-engineering
```

Expected: valid frontmatter, the reference file is present, and no placeholder match.

### Task 2: Link the behavior skill to Pulse knowledge and Task 3

**Files:**

- Modify: `antigravity/tasks/task-03-a1-ui-quality-review.md`
- Verify: `antigravity/skills/pulse-hardware-monitoring/SKILL.md`

- [ ] **Step 1: Add the dual-skill precondition**

Replace Task 3’s precondition with:

```markdown
先完整阅读并同时遵循：

1. `antigravity/skills/pulse-disciplined-engineering/SKILL.md`
2. `antigravity/skills/pulse-hardware-monitoring/SKILL.md`
3. `antigravity/skills/pulse-hardware-monitoring/references/pulse-current-state.md`
```

- [ ] **Step 2: Add the required behavior before code review**

Under “工作方式”, add this rule:

```markdown
在任何代码修改前，先按 `pulse-disciplined-engineering` 输出需求理解、事实/假设/未知项、影响分析和验证计划。只有发现 Critical 或 Important 问题并有失败证据时才修改代码；Minor 问题只记录，不扩大范围。
```

- [ ] **Step 3: Add an honest completion rule**

Add this acceptance criterion:

```markdown
- 不得以“代码已改好”作为结论；必须附上实际运行的测试、typecheck、build 与 lint 输出摘要。任何无法执行的验证必须明确说明原因和风险。
```

- [ ] **Step 4: Verify no task scope expanded**

Run:

```bash
rg -n 'Pulse Disciplined|需求理解|事实/假设/未知项|不得以“代码已改好”' \
  antigravity/tasks/task-03-a1-ui-quality-review.md
```

Expected: all three behavior requirements are present, while the existing “不在本任务范围内” section remains unchanged.

### Task 3: Validate portability and provide a handoff prompt

**Files:**

- Verify: `antigravity/skills/pulse-disciplined-engineering/SKILL.md`
- Verify: `antigravity/skills/pulse-hardware-monitoring/SKILL.md`
- Verify: `antigravity/tasks/task-03-a1-ui-quality-review.md`

- [ ] **Step 1: Run the bundled validator when its dependency is available**

Run:

```bash
python3 /Users/hlc/.codex/skills/.system/skill-creator/scripts/quick_validate.py \
  /Users/hlc/Documents/PulseProject/antigravity/skills/pulse-disciplined-engineering
```

Expected: validator reports success. If it cannot import `yaml`, do not install dependencies without authorization; report the unavailable validator and manually verify frontmatter, name, description and file tree.

- [ ] **Step 2: Perform the manual portability check**

Run:

```bash
for file in \
  antigravity/skills/pulse-disciplined-engineering/SKILL.md \
  antigravity/skills/pulse-disciplined-engineering/references/pulse-workflow-template.md \
  antigravity/skills/pulse-hardware-monitoring/SKILL.md \
  antigravity/tasks/task-03-a1-ui-quality-review.md; do
  test -s "$file" || exit 1
done
```

Expected: exit code 0.

- [ ] **Step 3: Deliver the exact Antigravity handoff**

Provide this prompt, replacing no paths:

```text
请先完整阅读并严格遵循：
1. /Users/hlc/Documents/PulseProject/antigravity/skills/pulse-disciplined-engineering/SKILL.md
2. /Users/hlc/Documents/PulseProject/antigravity/skills/pulse-hardware-monitoring/SKILL.md
3. /Users/hlc/Documents/PulseProject/antigravity/skills/pulse-hardware-monitoring/references/pulse-current-state.md

再执行：
/Users/hlc/Documents/PulseProject/antigravity/tasks/task-03-a1-ui-quality-review.md

禁止立即改代码。先输出需求理解、事实/假设/未知项、影响分析和验证计划；只有 Critical 或 Important 问题有失败证据时才作最小修复。不要提交 Git。
```

### Plan self-review

- Spec coverage: Task 1 implements behavior gates and templates; Task 2 connects both skills to the remaining Task 3; Task 3 validates portability and gives the exact handoff.
- Placeholder scan: no unfinished sections or unbound names remain.
- Scope: only Markdown skill/task assets change; Pulse product code, Git history and external systems are untouched.
