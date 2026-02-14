# Devcontainer Test Runs

Timestamped logs from automated devcontainer test suite. Each run (`YYYYMMDD_HHMMSS`) contains:
- `post-create.log`, `post-attach.log` - Command execution logs
- `spark-shell.log` - Spark SELECT 1 query validation
- `livy-health.log` - Livy server health check (port 8998)

## Run Tests
```bash
npx nx run devcontainer:test
```

## Fixed Issues
Permission errors resolved by setting vscode:vscode ownership on `/opt/spark/conf` and `/opt/livy/conf`.
