# CI Cache Checkpoint - 2026-06-02

Short checkpoint for the next CI cache iteration.

## Comparable run durations

| Run | Comparable total duration | Note |
| --- | --- | --- |
| 644 | about 40m06s | Earlier baseline |
| 645 | about 31m14s | Faster overall |
| 646 | about 31m34s | Latest attempt, still faster overall than 644 |

## Current findings

- The last two comparable runs, 645 and 646, were faster overall than 644.
- Windows Cargo restore still did not work on both measured recent runs.
- Run 645 used `v3` and still showed `api-visible/action-miss` on both Windows targets.
- Run 646 latest attempt used `v4` and still showed `api-visible/action-miss` on both Windows targets.
- Rotating the namespace escaped stale `v3` entries, but it did not fix restore behavior.
- The current overall speedup appears to come from variation in the slowest build legs, especially macOS Intel, not from a verified Windows cache hit.

## Next steps

- Investigate restore path, cache version, and path-coupling behavior on the Windows Cargo cache keys.
- Compare the saved cache metadata and restore inputs for the Windows targets side by side.
- Avoid more identical reruns until the restore-path/version coupling is explained.