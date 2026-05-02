---
name: create-skill
description: Creates a new Claude Code skill following official best practices. Use when the user wants to create, scaffold, or write a new skill.
disable-model-invocation: true
argument-hint: [skill-name] [description of what the skill should do]
---

Before writing any skill files, read the complete best practices guide: [reference.md](reference.md)

Create a new skill for: $ARGUMENTS

## Steps

1. Read [reference.md](reference.md) thoroughly
2. Ask the user clarifying questions if the skill purpose is ambiguous
3. Create the skill directory at `.claude/skills/$0/`
4. Write `SKILL.md` with proper frontmatter and concise instructions
5. Create any supporting files (templates, scripts, references) in the skill directory if needed
6. Verify the skill follows the checklist at the end of the guide
