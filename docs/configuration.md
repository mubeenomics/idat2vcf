# Configuration and logging reference

Environment settings and logging details.

[Usage](usage.md) · [Quick start](../README.md) · [Resources](resources.md)

## Path variables

Defaults may be overridden using Docker `-e` options:

| Variable | Default | Purpose |
|---|---|---|
| `DATA_DIR` | `/data` | Contains `idat_files/`, outputs, and run intermediates |
| `LOG_DIR` | `/container_logs` | Persistent logs; created if missing |
| `IDAT2VCF_RESOURCES_DIR` | `/idat2vcf_resources` | Exact resource set used at build time |
| `HOST_LOG_DIR` | Best-effort auto-detection | Host directory of the log mount, shown in status lines; pass it explicitly for NAS or nested mounts |

The documented commands pass `HOST_LOG_DIR` explicitly, which is reliable for
every mount layout. The auto-detection reads the bind-mount source from
`/proc/self/mountinfo` and shows the container path when the source cannot be
resolved. Non-absolute `HOST_LOG_DIR` values are rejected before any files are
created.

## Logging

The pipeline sources a pinned, checksum-verified copy of
[logshuru v2.0.0](https://github.com/mubeenomics/logshuru/releases/tag/v2.0.0).
No runtime download is required. Pipeline events include a millisecond timestamp,
severity, source file, function, and line number, for example:

```text
2026-10-26 12:00:00.123 | PROCESS  | idat2vcf:main:327 - Starting IDAT to GTC conversion
```

Stage events use `PROCESS`, informational summaries use `INFO`, the working path
and indexed record count use `DEBUG`, post-cleanup completion uses `SUCCESS`,
interruptions use `WARNING`, and failures use `ERROR`. Direct event calls retain
their actual source location. bcftools version information is logged as one
compact event instead of printing the full copyright banner. The formatted
completion event is written only to the run log; the console receives a single
final summary line, avoiding duplicate completion messages.

### Logger settings

| Variable | Default | Purpose |
|---|---|---|
| `LOG_LEVEL` | `PROCESS` | Minimum event severity; use `DEBUG` for additional details |
| `LOGSHURU_TZ` | `UTC` | Event timestamp timezone |
| `LOGSHURU_TIMESTAMP_FORMAT` | `%F %T.%3N` | GNU date timestamp format |
| `LOGSHURU_COLOR` | `never` | Plain logs by default; upstream also accepts `auto`/`always` |
| `LOGSHURU_OUTPUT` | `stderr` | Logger stream before combined run capture |
| `LOGSHURU_FORMAT` | `text` | Event format, `text` or `json` |

For example, add `-e LOG_LEVEL=DEBUG` to the run command. Severity order is
`TRACE → DEBUG → PROCESS → INFO → SUCCESS → WARNING → ERROR → CRITICAL`.

### Run-log capture

The unique `.log` file retains **both application events and raw bcftools
diagnostics** in both modes. Quiet execution redirects directly to the file;
`--verbose` additionally streams through `tee`. Console visibility is
independent of `LOG_LEVEL`: that setting filters application events, not raw
tool messages or the final console status. `LOGSHURU_FILE` is intentionally
disabled by the pipeline to avoid duplicate copies of events; `LOG_DIR` selects
the run-log directory. JSON mode applies only to application events: the
combined log still contains plain tool output and is **not** a JSON Lines file.

### Failure semantics

ERROR events do not implicitly exit. The pipeline explicitly handles failure,
preserves command exit status, and releases its lock even when error/cleanup
logging itself fails. A normal unhandled logger failure also stops the run under
strict mode. Invalid logger configuration fails before the project lock is
acquired and produces a failure summary pointing to its diagnostic log. Verbose
capture failures return nonzero without masking an existing tool error.
