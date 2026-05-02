---
name: commit-and-push
description: Interactive commit workflow that supports grouping changes into multiple commits or committing all at once. Inspects diffs, optionally links to issues, manages branch creation, and writes conventional commit messages (feat/fix/docs/etc).
allowed-tools: [Bash, Read, AskUserQuestion]
---

# Commit and Push

An interactive commit workflow. Follow each step in order. Use AskUserQuestion for all user prompts.

## Step 1: Commit Mode

Ask the user:

> Do you want to group changes into multiple commits, or commit all changes together?

Options: "Commit all changes together", "Group into multiple commits"

If **group commits** — jump to the [Grouped Commits Flow](#grouped-commits-flow).
If **commit all** — continue to Step 2.

---

## Step 2: Issue Linking

Ask the user:

> Are these changes tied to a GitHub issue?

Options: "Yes", "No"

If **yes**, ask for the issue number (e.g. `31`). Store it for the commit message.

---

## Step 3: Inspect Changes

Run `git diff` and `git diff --cached` to see all staged and unstaged changes. Read and understand what changed — the files modified, the nature of the changes (new feature, bug fix, docs, refactor, etc.). This understanding drives the commit message and branch name.

Then run `git add .` to stage everything.

---

## Step 4: Branch Check

Run `git branch --show-current` to check the current branch.

If on **main** or **master**, ask the user:

> You're on the main branch. Do you want to create and switch to a new branch?

Options: "Yes, create a new branch", "No, stay on main"

If **yes**: using your understanding of the diff from Step 3, generate a descriptive branch name in the format `type/short-description` (e.g. `feat/add-user-auth`, `fix/login-redirect`). Run `git checkout -b <branch-name>`.

---

## Step 5: Write Commit Message

Using your understanding of the changes from Step 3, write a conventional commit message.

**Format (no issue):**
```
type: short summary

More detailed description of what changed and why.
```

**Format (with issue from Step 2):**
```
type: [Issue #N] short summary

More detailed description of what changed and why.
```

Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`, `ci`, `build`

Choose the type that best matches the changes. The short summary should be lowercase, imperative mood, no period. The detailed description should explain what changed and the motivation.

**Important:** Do NOT add a `Co-Authored-By` trailer.

---

## Step 6: Commit and Push

Run `git commit` with the message from Step 5.

Then ask the user:

> Do you want to push to remote?

Options: "Yes", "No"

If **yes**, run `git push -u origin <current-branch>`.

---

## Grouped Commits Flow

When the user chose to group changes into multiple commits:

### G1: Inspect All Changes

Run `git diff` and `git diff --cached` to see everything. Analyze all the changes across all files.

### G2: Propose Groupings

Based on your analysis, propose logical groupings of the changes. Present them to the user. Each group should represent a coherent unit of work (e.g. "frontend styling changes", "API endpoint additions", "test updates").

Ask the user to confirm or adjust the groupings.

### G3: Branch Check (once)

Same as Step 4 above — check if on main/master and offer to create a branch. Do this once before any commits.

### G4: Issue Linking (once)

Same as Step 2 above — ask if changes are tied to an issue. The issue number applies to all grouped commits.

### G5: Commit Each Group

For each group, in order:

1. Stage only the files in that group using `git add <file1> <file2> ...` (do NOT use `git add .`)
2. Write a conventional commit message for that group following the format from Step 5
3. Run `git commit`

### G6: Push

Same as Step 6 — ask if the user wants to push, and push if yes.
