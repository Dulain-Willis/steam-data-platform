# Docker Compose Decisions

## Minio uses a bind mount, not a Docker volume

Minio is mounted via a bind mount to `.mnt/minio` on the host filesystem rather than a named Docker volume.

This means the data lives as regular files on disk, visible and accessible without Docker. Tearing down containers, pruning volumes, or recreating the stack does not affect the data. A Docker volume would tie the data to Docker's internal storage, making it invisible on the host and at risk of accidental deletion via `docker volume prune`.

For a service like Minio that holds the project's raw landing data, a bind mount is safer and easier to inspect or back up.
