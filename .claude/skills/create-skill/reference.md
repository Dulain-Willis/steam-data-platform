# How to Write Claude Code Skills — Complete Guide

## References

- [Agent Skills Best Practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills)

---

## What Are Skills?

Skills extend what Claude can do. Create a `SKILL.md` file with instructions, and Claude adds it to its toolkit. Claude uses skills when relevant, or you can invoke one directly with `/skill-name`.

> Create a skill when you keep pasting the same playbook, checklist, or multi-step procedure into chat, or when a section of CLAUDE.md has grown into a procedure rather than a fact. Unlike CLAUDE.md content, a skill's body loads only when it's used, so long reference material costs almost nothing until you need it.

Claude Code skills follow the [Agent Skills](https://agentskills.io) open standard.

---

## Skill Directory Structure

Each skill is a directory with `SKILL.md` as the entrypoint:

```text
my-skill/
├── SKILL.md           # Main instructions (required)
├── template.md        # Template for Claude to fill in
├── examples/
│   └── sample.md      # Example output showing expected format
└── scripts/
    └── validate.sh    # Script Claude can execute
```

> The `SKILL.md` contains the main instructions and is required. Other files are optional and let you build more powerful skills: templates for Claude to fill in, example outputs showing the expected format, scripts Claude can execute, or detailed reference documentation. Reference these files from your `SKILL.md` so Claude knows what they contain and when to load them.

---

## Where Skills Live

Where you store a skill determines who can use it:

| Location   | Path                                                | Applies to                     |
| :--------- | :-------------------------------------------------- | :----------------------------- |
| Enterprise | See managed settings                                | All users in your organization |
| Personal   | `~/.claude/skills/<skill-name>/SKILL.md`            | All your projects              |
| Project    | `.claude/skills/<skill-name>/SKILL.md`              | This project only              |
| Plugin     | `<plugin>/skills/<skill-name>/SKILL.md`             | Where plugin is enabled        |

> When skills share the same name across levels, enterprise overrides personal, and personal overrides project. Plugin skills use a `plugin-name:skill-name` namespace, so they cannot conflict with other levels.

### Live Change Detection

> Claude Code watches skill directories for file changes. Adding, editing, or removing a skill under `~/.claude/skills/`, the project `.claude/skills/`, or a `.claude/skills/` inside an `--add-dir` directory takes effect within the current session without restarting. Creating a top-level skills directory that did not exist when the session started requires restarting Claude Code so the new directory can be watched.

### Automatic Discovery from Nested Directories

> When you work with files in subdirectories, Claude Code automatically discovers skills from nested `.claude/skills/` directories. For example, if you're editing a file in `packages/frontend/`, Claude Code also looks for skills in `packages/frontend/.claude/skills/`. This supports monorepo setups where packages have their own skills.

---

## Core Principles

### 1. Concise is Key

> The context window is a public good. Your Skill shares the context window with everything else Claude needs to know, including: the system prompt, conversation history, other Skills' metadata, and your actual request.

> Not every token in your Skill has an immediate cost. At startup, only the metadata (name and description) from all Skills is pre-loaded. Claude reads SKILL.md only when the Skill becomes relevant, and reads additional files only as needed. However, being concise in SKILL.md still matters: once Claude loads it, every token competes with conversation history and other context.

**Default assumption: Claude is already very smart.** Only add context Claude doesn't already have. Challenge each piece of information:

- "Does Claude really need this explanation?"
- "Can I assume Claude knows this?"
- "Does this paragraph justify its token cost?"

**Good example — Concise** (~50 tokens):

````markdown
## Extract PDF text

Use pdfplumber for text extraction:

```python
import pdfplumber

with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```
````

**Bad example — Too verbose** (~150 tokens):

```markdown
## Extract PDF text

PDF (Portable Document Format) files are a common file format that contains
text, images, and other content. To extract text from a PDF, you'll need to
use a library. There are many libraries available for PDF processing, but
pdfplumber is recommended because it's easy to use and handles most cases well.
First, you'll need to install it using pip. Then you can use the code below...
```

> The concise version assumes Claude knows what PDFs are and how libraries work.

### 2. Set Appropriate Degrees of Freedom

> Match the level of specificity to the task's fragility and variability.

**High freedom** (text-based instructions) — Use when multiple approaches are valid, decisions depend on context, or heuristics guide the approach:

```markdown
## Code review process

1. Analyze the code structure and organization
2. Check for potential bugs or edge cases
3. Suggest improvements for readability and maintainability
4. Verify adherence to project conventions
```

**Medium freedom** (pseudocode or scripts with parameters) — Use when a preferred pattern exists but some variation is acceptable:

````markdown
## Generate report

Use this template and customize as needed:

```python
def generate_report(data, format="markdown", include_charts=True):
    # Process data
    # Generate output in specified format
    # Optionally include visualizations
```
````

**Low freedom** (specific scripts, few or no parameters) — Use when operations are fragile and error-prone, consistency is critical, or a specific sequence must be followed:

````markdown
## Database migration

Run exactly this script:

```bash
python scripts/migrate.py --verify --backup
```

Do not modify the command or add additional flags.
````

> **Analogy:** Think of Claude as a robot exploring a path:
> - **Narrow bridge with cliffs on both sides:** There's only one safe way forward. Provide specific guardrails and exact instructions (low freedom). Example: database migrations that must run in exact sequence.
> - **Open field with no hazards:** Many paths lead to success. Give general direction and trust Claude to find the best route (high freedom). Example: code reviews where context determines the best approach.

### 3. Test with All Models You Plan to Use

> Skills act as additions to models, so effectiveness depends on the underlying model. Test your Skill with all the models you plan to use it with.

- **Claude Haiku** (fast, economical): Does the Skill provide enough guidance?
- **Claude Sonnet** (balanced): Is the Skill clear and efficient?
- **Claude Opus** (powerful reasoning): Does the Skill avoid over-explaining?

> What works perfectly for Opus might need more detail for Haiku. If you plan to use your Skill across multiple models, aim for instructions that work well with all of them.

---

## YAML Frontmatter — The `SKILL.md` Header

Every `SKILL.md` starts with YAML frontmatter between `---` markers:

```yaml
---
name: my-skill
description: What this skill does
disable-model-invocation: true
allowed-tools: Read Grep
---

Your skill instructions here...
```

### Frontmatter Field Reference

All fields are optional. Only `description` is recommended so Claude knows when to use the skill.

| Field                      | Required    | Description                                                                                                                                                                                    |
| :------------------------- | :---------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `name`                     | No          | Display name. If omitted, uses the directory name. Lowercase letters, numbers, and hyphens only (max 64 chars). Cannot contain "anthropic" or "claude".                                        |
| `description`              | Recommended | What the skill does and when to use it. Claude uses this to decide when to apply the skill. If omitted, uses the first paragraph of content. Combined with `when_to_use`, truncated at 1,536 chars. |
| `when_to_use`              | No          | Additional context for when Claude should invoke the skill. Appended to `description` and counts toward the 1,536-char cap.                                                                    |
| `argument-hint`            | No          | Hint shown during autocomplete. Example: `[issue-number]` or `[filename] [format]`.                                                                                                           |
| `arguments`                | No          | Named positional arguments for `$name` substitution. Accepts a space-separated string or YAML list.                                                                                            |
| `disable-model-invocation` | No          | Set to `true` to prevent Claude from automatically loading this skill. Use for workflows you want to trigger manually. Default: `false`.                                                       |
| `user-invocable`           | No          | Set to `false` to hide from the `/` menu. Use for background knowledge users shouldn't invoke directly. Default: `true`.                                                                       |
| `allowed-tools`            | No          | Tools Claude can use without asking permission when this skill is active. Accepts a space-separated string or YAML list.                                                                       |
| `model`                    | No          | Model to use when this skill is active. Accepts same values as `/model`, or `inherit` to keep active model.                                                                                    |
| `effort`                   | No          | Effort level when this skill is active. Options: `low`, `medium`, `high`, `xhigh`, `max`.                                                                                                     |
| `context`                  | No          | Set to `fork` to run in a forked subagent context.                                                                                                                                             |
| `agent`                    | No          | Which subagent type to use when `context: fork` is set.                                                                                                                                        |
| `hooks`                    | No          | Hooks scoped to this skill's lifecycle.                                                                                                                                                        |
| `paths`                    | No          | Glob patterns that limit when this skill is activated. Claude loads the skill automatically only when working with files matching the patterns.                                                 |
| `shell`                    | No          | Shell to use for inline shell commands. Accepts `bash` (default) or `powershell`.                                                                                                              |

### Validation Rules for `name`

- Maximum 64 characters
- Must contain only lowercase letters, numbers, and hyphens
- Cannot contain XML tags
- Cannot contain reserved words: "anthropic", "claude"

### Validation Rules for `description`

- Must be non-empty
- Maximum 1024 characters
- Cannot contain XML tags
- Should describe what the Skill does AND when to use it

---

## Naming Conventions

> Use consistent naming patterns to make Skills easier to reference and discuss. Consider using **gerund form** (verb + -ing) for Skill names, as this clearly describes the activity or capability the Skill provides.

**Good naming examples (gerund form):**
- `processing-pdfs`
- `analyzing-spreadsheets`
- `managing-databases`
- `testing-code`
- `writing-documentation`

**Acceptable alternatives:**
- Noun phrases: `pdf-processing`, `spreadsheet-analysis`
- Action-oriented: `process-pdfs`, `analyze-spreadsheets`

**Avoid:**
- Vague names: `helper`, `utils`, `tools`
- Overly generic: `documents`, `data`, `files`
- Reserved words: `anthropic-helper`, `claude-tools`
- Inconsistent patterns within your skill collection

---

## Writing Effective Descriptions

> The `description` field enables Skill discovery and should include both what the Skill does and when to use it.

**Always write in third person.** The description is injected into the system prompt, and inconsistent point-of-view can cause discovery problems.

- **Good:** "Processes Excel files and generates reports"
- **Avoid:** "I can help you process Excel files"
- **Avoid:** "You can use this to process Excel files"

> Each Skill has exactly one description field. The description is critical for skill selection: Claude uses it to choose the right Skill from potentially 100+ available Skills. Your description must provide enough detail for Claude to know when to select this Skill, while the rest of SKILL.md provides the implementation details.

**Good descriptions:**

```yaml
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
```

```yaml
description: Analyze Excel spreadsheets, create pivot tables, generate charts. Use when analyzing Excel files, spreadsheets, tabular data, or .xlsx files.
```

```yaml
description: Generate descriptive commit messages by analyzing git diffs. Use when the user asks for help writing commit messages or reviewing staged changes.
```

**Bad descriptions:**

```yaml
description: Helps with documents
```
```yaml
description: Processes data
```
```yaml
description: Does stuff with files
```

---

## Progressive Disclosure Patterns

> SKILL.md serves as an overview that points Claude to detailed materials as needed, like a table of contents in an onboarding guide.

**Keep SKILL.md body under 500 lines for optimal performance.** Split content into separate files when approaching this limit.

### Pattern 1: High-Level Guide with References

````markdown
---
name: pdf-processing
description: Extracts text and tables from PDF files, fills forms, and merges documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
---

# PDF Processing

## Quick start

Extract text with pdfplumber:
```python
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```

## Advanced features

**Form filling**: See [FORMS.md](FORMS.md) for complete guide
**API reference**: See [REFERENCE.md](REFERENCE.md) for all methods
**Examples**: See [EXAMPLES.md](EXAMPLES.md) for common patterns
````

> Claude loads FORMS.md, REFERENCE.md, or EXAMPLES.md only when needed.

### Pattern 2: Domain-Specific Organization

> For Skills with multiple domains, organize content by domain to avoid loading irrelevant context. When a user asks about sales metrics, Claude only needs to read sales-related schemas, not finance or marketing data. This keeps token usage low and context focused.

```text
bigquery-skill/
├── SKILL.md (overview and navigation)
└── reference/
    ├── finance.md (revenue, billing metrics)
    ├── sales.md (opportunities, pipeline)
    ├── product.md (API usage, features)
    └── marketing.md (campaigns, attribution)
```

````markdown
# BigQuery Data Analysis

## Available datasets

**Finance**: Revenue, ARR, billing → See [reference/finance.md](reference/finance.md)
**Sales**: Opportunities, pipeline, accounts → See [reference/sales.md](reference/sales.md)
**Product**: API usage, features, adoption → See [reference/product.md](reference/product.md)
**Marketing**: Campaigns, attribution, email → See [reference/marketing.md](reference/marketing.md)

## Quick search

Find specific metrics using grep:

```bash
grep -i "revenue" reference/finance.md
grep -i "pipeline" reference/sales.md
grep -i "api usage" reference/product.md
```
````

### Pattern 3: Conditional Details

```markdown
# DOCX Processing

## Creating documents

Use docx-js for new documents. See [DOCX-JS.md](DOCX-JS.md).

## Editing documents

For simple edits, modify the XML directly.

**For tracked changes**: See [REDLINING.md](REDLINING.md)
**For OOXML details**: See [OOXML.md](OOXML.md)
```

> Claude reads REDLINING.md or OOXML.md only when the user needs those features.

### Avoid Deeply Nested References

> Claude may partially read files when they're referenced from other referenced files. When encountering nested references, Claude might use commands like `head -100` to preview content rather than reading entire files, resulting in incomplete information.

**Keep references one level deep from SKILL.md.**

**Bad — Too deep:**
```markdown
# SKILL.md
See [advanced.md](advanced.md)...

# advanced.md
See [details.md](details.md)...

# details.md
Here's the actual information...
```

**Good — One level deep:**
```markdown
# SKILL.md

**Basic usage**: [instructions in SKILL.md]
**Advanced features**: See [advanced.md](advanced.md)
**API reference**: See [reference.md](reference.md)
**Examples**: See [examples.md](examples.md)
```

### Structure Longer Reference Files with Table of Contents

> For reference files longer than 100 lines, include a table of contents at the top. This ensures Claude can see the full scope of available information even when previewing with partial reads.

```markdown
# API Reference

## Contents
- Authentication and setup
- Core methods (create, read, update, delete)
- Advanced features (batch operations, webhooks)
- Error handling patterns
- Code examples

## Authentication and setup
...

## Core methods
...
```

---

## Controlling Who Invokes a Skill

> By default, both you and Claude can invoke any skill. You can type `/skill-name` to invoke it directly, and Claude can load it automatically when relevant to your conversation.

Two frontmatter fields let you restrict this:

- **`disable-model-invocation: true`**: Only you can invoke the skill. Use for workflows with side effects or that you want to control timing, like `/commit`, `/deploy`, or `/send-slack-message`. You don't want Claude deciding to deploy because your code looks ready.

- **`user-invocable: false`**: Only Claude can invoke the skill. Use for background knowledge that isn't actionable as a command. A `legacy-system-context` skill explains how an old system works. Claude should know this when relevant, but `/legacy-system-context` isn't a meaningful action for users to take.

| Frontmatter                      | You can invoke | Claude can invoke | When loaded into context                                     |
| :------------------------------- | :------------- | :---------------- | :----------------------------------------------------------- |
| (default)                        | Yes            | Yes               | Description always in context, full skill loads when invoked |
| `disable-model-invocation: true` | Yes            | No                | Description not in context, full skill loads when you invoke |
| `user-invocable: false`          | No             | Yes               | Description always in context, full skill loads when invoked |

---

## Skill Content Lifecycle

> When you or Claude invoke a skill, the rendered `SKILL.md` content enters the conversation as a single message and stays there for the rest of the session. Claude Code does not re-read the skill file on later turns, so write guidance that should apply throughout a task as standing instructions rather than one-time steps.

> Auto-compaction carries invoked skills forward within a token budget. When the conversation is summarized to free context, Claude Code re-attaches the most recent invocation of each skill after the summary, keeping the first 5,000 tokens of each. Re-attached skills share a combined budget of 25,000 tokens. Claude Code fills this budget starting from the most recently invoked skill, so older skills can be dropped entirely after compaction if you have invoked many in one session.

> If a skill seems to stop influencing behavior after the first response, the content is usually still present and the model is choosing other tools or approaches. Strengthen the skill's `description` and instructions so the model keeps preferring it, or use hooks to enforce behavior deterministically. If the skill is large or you invoked several others after it, re-invoke it after compaction to restore the full content.

---

## String Substitutions

Skills support string substitution for dynamic values:

| Variable               | Description                                                                                  |
| :--------------------- | :------------------------------------------------------------------------------------------- |
| `$ARGUMENTS`           | All arguments passed when invoking the skill.                                                |
| `$ARGUMENTS[N]`        | Access a specific argument by 0-based index.                                                 |
| `$N`                   | Shorthand for `$ARGUMENTS[N]`.                                                               |
| `$name`                | Named argument declared in the `arguments` frontmatter list.                                 |
| `${CLAUDE_SESSION_ID}` | The current session ID.                                                                      |
| `${CLAUDE_EFFORT}`     | The current effort level: `low`, `medium`, `high`, `xhigh`, or `max`.                       |
| `${CLAUDE_SKILL_DIR}`  | The directory containing the skill's `SKILL.md` file.                                        |

> Indexed arguments use shell-style quoting, so wrap multi-word values in quotes to pass them as a single argument.

**Example — Passing arguments:**

```yaml
---
name: fix-issue
description: Fix a GitHub issue
disable-model-invocation: true
---

Fix GitHub issue $ARGUMENTS following our coding standards.

1. Read the issue description
2. Understand the requirements
3. Implement the fix
4. Write tests
5. Create a commit
```

> When you run `/fix-issue 123`, Claude receives "Fix GitHub issue 123 following our coding standards..."

**Example — Positional arguments:**

```yaml
---
name: migrate-component
description: Migrate a component from one framework to another
---

Migrate the $0 component from $1 to $2.
Preserve all existing behavior and tests.
```

> Running `/migrate-component SearchBar React Vue` replaces `$0` with `SearchBar`, `$1` with `React`, and `$2` with `Vue`.

---

## Pre-Approving Tools for a Skill

> The `allowed-tools` field grants permission for the listed tools while the skill is active, so Claude can use them without prompting you for approval. It does not restrict which tools are available.

```yaml
---
name: commit
description: Stage and commit the current changes
disable-model-invocation: true
allowed-tools: Bash(git add *) Bash(git commit *) Bash(git status *)
---
```

---

## Injecting Dynamic Context

> The `` !`<command>` `` syntax runs shell commands before the skill content is sent to Claude. The command output replaces the placeholder, so Claude receives actual data, not the command itself.

```yaml
---
name: pr-summary
description: Summarize changes in a pull request
context: fork
agent: Explore
allowed-tools: Bash(gh *)
---

## Pull request context
- PR diff: !`gh pr diff`
- PR comments: !`gh pr view --comments`
- Changed files: !`gh pr diff --name-only`

## Your task
Summarize this pull request...
```

> When this skill runs:
> 1. Each `` !`<command>` `` executes immediately (before Claude sees anything)
> 2. The output replaces the placeholder in the skill content
> 3. Claude receives the fully-rendered prompt with actual PR data

For multi-line commands, use a fenced code block opened with ` ```! `:

````markdown
## Environment
```!
node --version
npm --version
git status --short
```
````

---

## Running Skills in a Subagent

> Add `context: fork` to your frontmatter when you want a skill to run in isolation. The skill content becomes the prompt that drives the subagent. It won't have access to your conversation history.

> **Warning:** `context: fork` only makes sense for skills with explicit instructions. If your skill contains guidelines like "use these API conventions" without a task, the subagent receives the guidelines but no actionable prompt, and returns without meaningful output.

| Approach                     | System prompt                             | Task                        | Also loads                   |
| :--------------------------- | :---------------------------------------- | :-------------------------- | :--------------------------- |
| Skill with `context: fork`   | From agent type (`Explore`, `Plan`, etc.) | SKILL.md content            | CLAUDE.md                    |
| Subagent with `skills` field | Subagent's markdown body                  | Claude's delegation message | Preloaded skills + CLAUDE.md |

**Example — Research skill using Explore agent:**

```yaml
---
name: deep-research
description: Research a topic thoroughly
context: fork
agent: Explore
---

Research $ARGUMENTS thoroughly:

1. Find relevant files using Glob and Grep
2. Read and analyze the code
3. Summarize findings with specific file references
```

> When this skill runs:
> 1. A new isolated context is created
> 2. The subagent receives the skill content as its prompt
> 3. The `agent` field determines the execution environment (model, tools, and permissions)
> 4. Results are summarized and returned to your main conversation

> The `agent` field specifies which subagent configuration to use. Options include built-in agents (`Explore`, `Plan`, `general-purpose`) or any custom subagent from `.claude/agents/`. If omitted, uses `general-purpose`.

---

## Workflows and Feedback Loops

### Use Workflows for Complex Tasks

> Break complex operations into clear, sequential steps. For particularly complex workflows, provide a checklist that Claude can copy into its response and check off as it progresses.

**Example — Research synthesis workflow (no code):**

````markdown
## Research synthesis workflow

Copy this checklist and track your progress:

```
Research Progress:
- [ ] Step 1: Read all source documents
- [ ] Step 2: Identify key themes
- [ ] Step 3: Cross-reference claims
- [ ] Step 4: Create structured summary
- [ ] Step 5: Verify citations
```

**Step 1: Read all source documents**

Review each document in the `sources/` directory. Note the main arguments and supporting evidence.

**Step 2: Identify key themes**

Look for patterns across sources. What themes appear repeatedly? Where do sources agree or disagree?

**Step 3: Cross-reference claims**

For each major claim, verify it appears in the source material. Note which source supports each point.

**Step 4: Create structured summary**

Organize findings by theme. Include:
- Main claim
- Supporting evidence from sources
- Conflicting viewpoints (if any)

**Step 5: Verify citations**

Check that every claim references the correct source document. If citations are incomplete, return to Step 3.
````

**Example — PDF form filling workflow (with code):**

````markdown
## PDF form filling workflow

Copy this checklist and check off items as you complete them:

```
Task Progress:
- [ ] Step 1: Analyze the form (run analyze_form.py)
- [ ] Step 2: Create field mapping (edit fields.json)
- [ ] Step 3: Validate mapping (run validate_fields.py)
- [ ] Step 4: Fill the form (run fill_form.py)
- [ ] Step 5: Verify output (run verify_output.py)
```

**Step 1: Analyze the form**

Run: `python scripts/analyze_form.py input.pdf`

This extracts form fields and their locations, saving to `fields.json`.

**Step 2: Create field mapping**

Edit `fields.json` to add values for each field.

**Step 3: Validate mapping**

Run: `python scripts/validate_fields.py fields.json`

Fix any validation errors before continuing.

**Step 4: Fill the form**

Run: `python scripts/fill_form.py input.pdf fields.json output.pdf`

**Step 5: Verify output**

Run: `python scripts/verify_output.py output.pdf`

If verification fails, return to Step 2.
````

### Implement Feedback Loops

> **Common pattern:** Run validator -> fix errors -> repeat. This pattern greatly improves output quality.

**Example — Style guide compliance (no code):**

```markdown
## Content review process

1. Draft your content following the guidelines in STYLE_GUIDE.md
2. Review against the checklist:
   - Check terminology consistency
   - Verify examples follow the standard format
   - Confirm all required sections are present
3. If issues found:
   - Note each issue with specific section reference
   - Revise the content
   - Review the checklist again
4. Only proceed when all requirements are met
5. Finalize and save the document
```

**Example — Document editing process (with code):**

```markdown
## Document editing process

1. Make your edits to `word/document.xml`
2. **Validate immediately**: `python ooxml/scripts/validate.py unpacked_dir/`
3. If validation fails:
   - Review the error message carefully
   - Fix the issues in the XML
   - Run validation again
4. **Only proceed when validation passes**
5. Rebuild: `python ooxml/scripts/pack.py unpacked_dir/ output.docx`
6. Test the output document
```

---

## Content Guidelines

### Avoid Time-Sensitive Information

**Bad — Time-sensitive (will become wrong):**
```markdown
If you're doing this before August 2025, use the old API.
After August 2025, use the new API.
```

**Good — Use "old patterns" section:**
```markdown
## Current method

Use the v2 API endpoint: `api.example.com/v2/messages`

## Old patterns

<details>
<summary>Legacy v1 API (deprecated 2025-08)</summary>

The v1 API used: `api.example.com/v1/messages`

This endpoint is no longer supported.
</details>
```

### Use Consistent Terminology

> Choose one term and use it throughout the Skill.

**Good — Consistent:**
- Always "API endpoint"
- Always "field"
- Always "extract"

**Bad — Inconsistent:**
- Mix "API endpoint", "URL", "API route", "path"
- Mix "field", "box", "element", "control"
- Mix "extract", "pull", "get", "retrieve"

---

## Common Patterns

### Template Pattern

> Provide templates for output format. Match the level of strictness to your needs.

**For strict requirements** (like API responses or data formats):

````markdown
## Report structure

ALWAYS use this exact template structure:

```markdown
# [Analysis Title]

## Executive summary
[One-paragraph overview of key findings]

## Key findings
- Finding 1 with supporting data
- Finding 2 with supporting data
- Finding 3 with supporting data

## Recommendations
1. Specific actionable recommendation
2. Specific actionable recommendation
```
````

**For flexible guidance** (when adaptation is useful):

````markdown
## Report structure

Here is a sensible default format, but use your best judgment based on the analysis:

```markdown
# [Analysis Title]

## Executive summary
[Overview]

## Key findings
[Adapt sections based on what you discover]

## Recommendations
[Tailor to the specific context]
```

Adjust sections as needed for the specific analysis type.
````

### Examples Pattern

> For Skills where output quality depends on seeing examples, provide input/output pairs just like in regular prompting.

````markdown
## Commit message format

Generate commit messages following these examples:

**Example 1:**
Input: Added user authentication with JWT tokens
Output:
```
feat(auth): implement JWT-based authentication

Add login endpoint and token validation middleware
```

**Example 2:**
Input: Fixed bug where dates displayed incorrectly in reports
Output:
```
fix(reports): correct date formatting in timezone conversion

Use UTC timestamps consistently across report generation
```

**Example 3:**
Input: Updated dependencies and refactored error handling
Output:
```
chore: update dependencies and refactor error handling

- Upgrade lodash to 4.17.21
- Standardize error response format across endpoints
```

Follow this style: type(scope): brief description, then detailed explanation.
````

> Examples help Claude understand the desired style and level of detail more clearly than descriptions alone.

### Conditional Workflow Pattern

```markdown
## Document modification workflow

1. Determine the modification type:

   **Creating new content?** → Follow "Creation workflow" below
   **Editing existing content?** → Follow "Editing workflow" below

2. Creation workflow:
   - Use docx-js library
   - Build document from scratch
   - Export to .docx format

3. Editing workflow:
   - Unpack existing document
   - Modify XML directly
   - Validate after each change
   - Repack when complete
```

> If workflows become large or complicated with many steps, consider pushing them into separate files and tell Claude to read the appropriate file based on the task at hand.

---

## Skills with Executable Code

### Solve, Don't Punt

> When writing scripts for Skills, handle error conditions rather than punting to Claude.

**Good — Handle errors explicitly:**

```python
def process_file(path):
    """Process a file, creating it if it doesn't exist."""
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        print(f"File {path} not found, creating default")
        with open(path, "w") as f:
            f.write("")
        return ""
    except PermissionError:
        print(f"Cannot access {path}, using default")
        return ""
```

**Bad — Punt to Claude:**

```python
def process_file(path):
    # Just fail and let Claude figure it out
    return open(path).read()
```

> Configuration parameters should also be justified and documented to avoid "voodoo constants" (Ousterhout's law). If you don't know the right value, how will Claude determine it?

**Good — Self-documenting:**

```python
# HTTP requests typically complete within 30 seconds
# Longer timeout accounts for slow connections
REQUEST_TIMEOUT = 30

# Three retries balances reliability vs speed
# Most intermittent failures resolve by the second retry
MAX_RETRIES = 3
```

**Bad — Magic numbers:**

```python
TIMEOUT = 47  # Why 47?
RETRIES = 5  # Why 5?
```

### Provide Utility Scripts

> Even if Claude could write a script, pre-made scripts offer advantages:
> - More reliable than generated code
> - Save tokens (no need to include code in context)
> - Save time (no code generation required)
> - Ensure consistency across uses

> **Important distinction:** Make clear in your instructions whether Claude should:
> - **Execute the script** (most common): "Run `analyze_form.py` to extract fields"
> - **Read it as reference** (for complex logic): "See `analyze_form.py` for the field extraction algorithm"

````markdown
## Utility scripts

**analyze_form.py**: Extract all form fields from PDF

```bash
python scripts/analyze_form.py input.pdf > fields.json
```

Output format:
```json
{
  "field_name": {"type": "text", "x": 100, "y": 200},
  "signature": {"type": "sig", "x": 150, "y": 500}
}
```

**validate_boxes.py**: Check for overlapping bounding boxes

```bash
python scripts/validate_boxes.py fields.json
# Returns: "OK" or lists conflicts
```

**fill_form.py**: Apply field values to PDF

```bash
python scripts/fill_form.py input.pdf fields.json output.pdf
```
````

### Create Verifiable Intermediate Outputs

> When Claude performs complex, open-ended tasks, it can make mistakes. The "plan-validate-execute" pattern catches errors early by having Claude first create a plan in a structured format, then validate that plan with a script before executing it.

**Why this pattern works:**
- **Catches errors early:** Validation finds problems before changes are applied
- **Machine-verifiable:** Scripts provide objective verification
- **Reversible planning:** Claude can iterate on the plan without touching originals
- **Clear debugging:** Error messages point to specific problems

**When to use:** Batch operations, destructive changes, complex validation rules, high-stakes operations.

> **Implementation tip:** Make validation scripts verbose with specific error messages like "Field 'signature_date' not found. Available fields: customer_name, order_total, signature_date_signed" to help Claude fix issues.

### Don't Assume Tools Are Installed

````markdown
**Bad — Assumes installation:**
"Use the pdf library to process the file."

**Good — Explicit about dependencies:**
"Install required package: `pip install pypdf`

Then use it:
```python
from pypdf import PdfReader
reader = PdfReader("file.pdf")
```"
````

### MCP Tool References

> If your Skill uses MCP (Model Context Protocol) tools, always use fully qualified tool names to avoid "tool not found" errors.

**Format:** `ServerName:tool_name`

```markdown
Use the BigQuery:bigquery_schema tool to retrieve table schemas.
Use the GitHub:create_issue tool to create issues.
```

---

## Evaluation and Iteration

### Build Evaluations First

> **Create evaluations BEFORE writing extensive documentation.** This ensures your Skill solves real problems rather than documenting imagined ones.

**Evaluation-driven development:**
1. **Identify gaps:** Run Claude on representative tasks without a Skill. Document specific failures or missing context
2. **Create evaluations:** Build three scenarios that test these gaps
3. **Establish baseline:** Measure Claude's performance without the Skill
4. **Write minimal instructions:** Create just enough content to address the gaps and pass evaluations
5. **Iterate:** Execute evaluations, compare against baseline, and refine

**Evaluation structure:**
```json
{
  "skills": ["pdf-processing"],
  "query": "Extract all text from this PDF file and save it to output.txt",
  "files": ["test-files/document.pdf"],
  "expected_behavior": [
    "Successfully reads the PDF file using an appropriate library or tool",
    "Extracts text content from all pages without missing any",
    "Saves the extracted text to output.txt in a clear, readable format"
  ]
}
```

### Develop Skills Iteratively with Claude

> The most effective Skill development process involves Claude itself. Work with one instance of Claude ("Claude A") to create a Skill that is used by other instances ("Claude B"). Claude A helps you design and refine instructions, while Claude B tests them in real tasks.

**Creating a new Skill:**

1. **Complete a task without a Skill:** Work through a problem with Claude A using normal prompting. Notice what information you repeatedly provide.
2. **Identify the reusable pattern:** After completing the task, identify what context you provided that would be useful for similar future tasks.
3. **Ask Claude A to create a Skill:** Claude models understand the Skill format and structure natively. You don't need special system prompts.
4. **Review for conciseness:** Check that Claude A hasn't added unnecessary explanations. Ask: "Remove the explanation about what win rate means - Claude already knows that."
5. **Improve information architecture:** Ask Claude A to organize the content more effectively. Example: "Organize this so the table schema is in a separate reference file."
6. **Test on similar tasks:** Use the Skill with Claude B (a fresh instance with the Skill loaded) on related use cases.
7. **Iterate based on observation:** If Claude B struggles or misses something, return to Claude A with specifics.

**Iterating on existing Skills:**

1. **Use the Skill in real workflows:** Give Claude B actual tasks, not test scenarios
2. **Observe Claude B's behavior:** Note where it struggles, succeeds, or makes unexpected choices
3. **Return to Claude A for improvements:** Share the current SKILL.md and describe what you observed
4. **Review Claude A's suggestions:** Claude A might suggest reorganizing to make rules more prominent, using stronger language, or restructuring the workflow section
5. **Apply and test changes:** Update the Skill with refinements, then test again with Claude B
6. **Repeat based on usage:** Continue this observe-refine-test cycle

> **Why this approach works:** Claude A understands agent needs, you provide domain expertise, Claude B reveals gaps through real usage, and iterative refinement improves Skills based on observed behavior rather than assumptions.

### Observe How Claude Navigates Skills

> As you iterate on Skills, pay attention to how Claude actually uses them in practice. Watch for:
> - **Unexpected exploration paths:** Does Claude read files in an order you didn't anticipate? This might indicate your structure isn't as intuitive as you thought
> - **Missed connections:** Does Claude fail to follow references to important files? Your links might need to be more explicit or prominent
> - **Overreliance on certain sections:** If Claude repeatedly reads the same file, consider whether that content should be in the main SKILL.md instead
> - **Ignored content:** If Claude never accesses a bundled file, it might be unnecessary or poorly signaled in the main instructions

> The 'name' and 'description' in your Skill's metadata are particularly critical. Claude uses these when deciding whether to trigger the Skill in response to the current task. Make sure they clearly describe what the Skill does and when it should be used.

---

## Anti-Patterns to Avoid

### Avoid Windows-Style Paths

Always use forward slashes in file paths, even on Windows:
- **Good:** `scripts/helper.py`, `reference/guide.md`
- **Avoid:** `scripts\helper.py`, `reference\guide.md`

### Avoid Offering Too Many Options

````markdown
**Bad — Too many choices (confusing):**
"You can use pypdf, or pdfplumber, or PyMuPDF, or pdf2image, or..."

**Good — Provide a default (with escape hatch):**
"Use pdfplumber for text extraction:
```python
import pdfplumber
```

For scanned PDFs requiring OCR, use pdf2image with pytesseract instead."
````

---

## Types of Skill Content

> **Reference content** adds knowledge Claude applies to your current work. Conventions, patterns, style guides, domain knowledge. This content runs inline so Claude can use it alongside your conversation context.

```yaml
---
name: api-conventions
description: API design patterns for this codebase
---

When writing API endpoints:
- Use RESTful naming conventions
- Return consistent error formats
- Include request validation
```

> **Task content** gives Claude step-by-step instructions for a specific action, like deployments, commits, or code generation. These are often actions you want to invoke directly with `/skill-name` rather than letting Claude decide when to run them. Add `disable-model-invocation: true` to prevent Claude from triggering it automatically.

```yaml
---
name: deploy
description: Deploy the application to production
context: fork
disable-model-invocation: true
---

Deploy the application:
1. Run the test suite
2. Build the application
3. Push to the deployment target
```

---

## Complete Getting Started Example

From the Claude Code docs, a skill that teaches Claude to explain code using visual diagrams and analogies:

```yaml
---
description: Explains code with visual diagrams and analogies. Use when explaining how code works, teaching about a codebase, or when the user asks "how does this work?"
---

When explaining code, always include:

1. **Start with an analogy**: Compare the code to something from everyday life
2. **Draw a diagram**: Use ASCII art to show the flow, structure, or relationships
3. **Walk through the code**: Explain step-by-step what happens
4. **Highlight a gotcha**: What's a common mistake or misconception?

Keep explanations conversational. For complex concepts, use multiple analogies.
```

---

## Checklist for Effective Skills

Before sharing a Skill, verify:

### Core Quality
- [ ] Description is specific and includes key terms
- [ ] Description includes both what the Skill does and when to use it
- [ ] Description is written in third person
- [ ] SKILL.md body is under 500 lines
- [ ] Additional details are in separate files (if needed)
- [ ] No time-sensitive information (or in "old patterns" section)
- [ ] Consistent terminology throughout
- [ ] Examples are concrete, not abstract
- [ ] File references are one level deep
- [ ] Progressive disclosure used appropriately
- [ ] Workflows have clear steps

### Code and Scripts
- [ ] Scripts solve problems rather than punt to Claude
- [ ] Error handling is explicit and helpful
- [ ] No "voodoo constants" (all values justified)
- [ ] Required packages listed in instructions and verified as available
- [ ] Scripts have clear documentation
- [ ] No Windows-style paths (all forward slashes)
- [ ] Validation/verification steps for critical operations
- [ ] Feedback loops included for quality-critical tasks

### Testing
- [ ] At least three evaluations created
- [ ] Tested with Haiku, Sonnet, and Opus
- [ ] Tested with real usage scenarios
- [ ] Team feedback incorporated (if applicable)

---

## Troubleshooting

### Skill Not Triggering

> 1. Check the description includes keywords users would naturally say
> 2. Verify the skill appears in `What skills are available?`
> 3. Try rephrasing your request to match the description more closely
> 4. Invoke it directly with `/skill-name` if the skill is user-invocable

### Skill Triggers Too Often

> 1. Make the description more specific
> 2. Add `disable-model-invocation: true` if you only want manual invocation

### Skill Descriptions Are Cut Short

> Skill descriptions are loaded into context so Claude knows what's available. All skill names are always included, but if you have many skills, descriptions are shortened to fit the character budget, which can strip the keywords Claude needs to match your request. The budget scales dynamically at 1% of the context window, with a fallback of 8,000 characters.

> To raise the limit, set the `SLASH_COMMAND_TOOL_CHAR_BUDGET` environment variable. Or trim the `description` and `when_to_use` text at the source: front-load the key use case, since each entry's combined text is capped at 1,536 characters regardless of budget.
