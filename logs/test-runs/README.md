# Devcontainer Test Runs

This directory contains test run logs from the automated devcontainer test suite.

## Test Suite Overview

The test suite (`npx nx run devcontainer:test`) validates the devcontainer setup by:

1. **Post-Create Validation**: Runs `/tmp/overlay/post-create-commands.sh`
   - Installs npm packages
   - Verifies Hatch Python tool installation

2. **Post-Attach Validation**: Runs `/tmp/overlay/post-attach-commands.sh`
   - Configures Spark defaults based on host resources
   - Sets up Livy server configuration
   - Starts Livy server on port 8998

3. **Spark Shell Test**: Executes `SELECT 1` query
   - Validates Spark is properly configured
   - Ensures config files are readable by vscode user

4. **Livy Health Check**: Verifies Livy server responds
   - Tests `http://localhost:8998/sessions` endpoint
   - Confirms REST API is operational

## Log Directory Structure

Each test run creates a timestamped directory (`YYYYMMDD_HHMMSS`) containing:

- `docker-run.log` - Container startup output
- `post-create.log` - Post-create command execution
- `post-attach.log` - Post-attach command execution (includes Livy startup)
- `spark-shell.log` - Spark shell test output
- `livy-health.log` - Livy health check response
- `cleanup.log` - Test environment teardown

## Issues Fixed

### Permission Denied Errors (RESOLVED)
Initial tests revealed permission issues where vscode user couldn't read config files:
- `/opt/spark/conf/spark-defaults.conf (Permission denied)`
- `/opt/livy/conf/livy-server-log4j.properties (Permission denied)`

**Solution**: Modified `post-attach-commands.sh` to:
- Set vscode:vscode ownership on `/opt/spark/conf` and `/opt/livy/conf` directories
- Use `sudo install -m 644 -o vscode -g vscode` when creating config files

## Running Tests

```bash
# Run the test suite
npx nx run devcontainer:test

# Rebuild and test in one go
npx nx run devcontainer:publish --skip-nx-cache && npx nx run devcontainer:test
```

## Test Success Criteria

✅ All tests pass when:
- Post-create command exits with code 0
- Post-attach command exits with code 0
- Spark shell successfully executes SELECT 1
- Livy responds to health check within 30 seconds
