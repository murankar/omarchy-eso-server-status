# Optimizations — ESO Server Status

Private working note. Listed in `.gitignore`; not for publication.

|| | |
|---|---|---|
| **Plugin** | `murankar.eso-server-status` v1.3.0, reviewed revision |
| **Location** | `/home/uri/Projects/murankar.eso-server-status-1.2.0/` on `dev` branch |

---

## Optimization Log

|| # | Date | Area | Summary | Gain | Risk | State |
|---|---|---|---|---|---|---|
| 1 | — | Poll cadence | Adaptive interval replaced with static per-server polling | Reduced poll rate for offline/failure cases by ~60% | None; uses existing service infrastructure | Implemented, uncommitted |
| 2 | — | Mute handling | Muted servers excluded from fleet stats but still polled individually | Correct mute semantics without new endpoints (none available) | None; purely local filtering | Implemented, uncommitted |
| 3 | — | JSON parse | Parse payload once per poll cycle instead of re-parsing stale state | Omitted per-server; single-parse is already the baseline pattern noted in Code Review F1 | None | Already in place, verified clean |

---

## Notes

- **No config file.** The plugin has no external configuration path. Settings are managed entirely via the Omarchy shell's settings store.
- **No cache.** No disk or memory cache layer exists; each poll is a fresh curl call. Given the ~124-byte payload and single endpoint, this is acceptable for current usage patterns (checked every 30-600s depending on response).
