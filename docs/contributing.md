# Contributing

## Docstrings

All Python modules and non-trivial functions must have docstrings. This project follows [PEP 257](https://peps.python.org/pep-0257/) conventions with [Google style](https://google.github.io/styleguide/pyguide#38-comments-and-docstrings) formatting.

**Module docstrings** go at the top of every file, before imports. They describe what the module is for and any key design decisions a reader should know upfront.

**Function docstrings** follow the Google sections:

```python
def my_function(param: str) -> int:
    """One-line summary ending with a period.

    Optional longer explanation when the summary alone is not enough to
    understand intent, side effects, or important constraints.

    Args:
        param: What this argument represents and any constraints on its value.

    Returns:
        What is returned and what it means.

    Raises:
        ValueError: When and why this is raised.
    """
```

**When to use a one-liner vs full sections:**

Use a **one-liner** when the function name and type annotations together make the behavior completely obvious — nothing would be added by elaborating. A private helper that wraps a single expression is a common case.

Add `Args:` / `Returns:` / `Raises:` when any of the following are true:
- A parameter's meaning or valid range is not obvious from its name and type alone
- The return value carries semantics beyond its type (e.g. a `SparkSession` that is pre-configured with S3A and Iceberg, not a vanilla one)
- The function can raise exceptions a caller should handle
- The function has side effects (I/O, state mutation, environment reads) that are not apparent from the signature

When type annotations are present you do **not** need to repeat the types inside `Args:` — Google style says to omit them to avoid duplication.

## Commit Message Format

All commits follow this format:

    [Issue #N]
    type: short imperative description

      One or two sentences explaining the motivation — what problem this
      solves or what goal it achieves, not just what changed.

      - Bullet per logical change group (file or subsystem level)
      - Start with a verb: Add, Delete, Revert, Update, Fix, etc.
      - Include the why when it is not obvious from the bullet itself

**Types:** `feat`, `fix`, `refactor`, `docs`, `chore`

**Example:**

    [Issue #17]
    fix: repair steamspy bronze/silver pipeline end-to-end

      Bronze writer was emitting Parquet with a mismatched schema after the
      landing bucket rename, causing the silver job to fail on read.

      - Fix partition path construction in bronze writer to use new bucket name
      - Update silver reader schema to match bronze output column order
      - Add end-to-end smoke test that runs both stages against fixture data
