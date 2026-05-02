# Edit Plan

Interactive plan editor with approval gates before making changes.

## Workflow

1. **Get inputs** — If edits file and/or plan file not provided as arguments, ask the user for them
   - Edits file can be any path (relative or absolute)
   - Plan file is fuzzy-matched in `/docs/plans/` directories if only a partial name is given

2. **Show available edits** — Parse the edits file and list all numbered edits
   - Look for markers like `## 1`, `## 2`, etc.
   - Display each edit's heading/title

3. **Get selection** — Ask the user which edit number they want to apply

4. **Display context** — Show:
   - The full edit description from the edits file
   - The entire current plan file (so user can see what they're editing)

5. **Preview changes** — Before making any edits, show:
   - Every exact change that will be made (line-by-line diffs)
   - Why each change is being made (from the edit description)

6. **Get approval** — Ask the user to confirm before proceeding

7. **Apply edits** — Once approved, make the actual file modifications

## Edit File Format

Mark edits with `##` followed by the number:

```
## 1
First edit description.
What should change and why.

## 2
Second edit description.
Details about this edit.
```

## Example Usage

```
/edit-plan edits.md my-plan.md
# or with fuzzy matching:
/edit-plan edits.md my-plan
# or be asked for both:
/edit-plan
```

## Notes

- Partial filenames work for plan files
- Neither filename has to be an exact match
- Plan files are searched in `docs/plans/` subdirectories
- All changes require explicit approval before proceeding
