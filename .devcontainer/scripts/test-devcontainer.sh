#!/bin/bash -e

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
DEVCONTAINER_DIR=$(dirname "$SCRIPT_DIR")
WORKSPACE_ROOT=$(dirname "$DEVCONTAINER_DIR")

# Generate timestamp for this test run
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${WORKSPACE_ROOT}/logs/test-runs/${TIMESTAMP}"
mkdir -p "$LOG_DIR"

# Read the devcontainer image from devcontainer.json
DEVCONTAINER_IMAGE=$(grep -oP '"image":\s*"\K[^"]+' "${DEVCONTAINER_DIR}/devcontainer.json")

if [ -z "$DEVCONTAINER_IMAGE" ]; then
    echo "ERROR: Could not read image from devcontainer.json"
    exit 1
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  DEVCONTAINER TEST SUITE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Image:     $DEVCONTAINER_IMAGE"
echo "  Timestamp: $TIMESTAMP"
echo "  Logs:      $LOG_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Cleanup function
cleanup() {
    echo
    echo "Cleaning up test environment..."
    docker rm -f spark-devcontainer-test 2>&1 | tee -a "$LOG_DIR/cleanup.log" || true
    rm -rf /tmp/test-workspace 2>/dev/null || true
}

trap cleanup EXIT

# Setup test workspace
echo "[1/7] Setting up test workspace..."
rm -rf /tmp/test-workspace 2>/dev/null || true
mkdir -p /tmp/test-workspace
cd /tmp/test-workspace
git init -q
git config user.email "test@example.com"
git config user.name "Test User"
touch README.md
git add README.md
git commit -q -m "Initial commit"

# Create minimal package.json for post-create
cat > package.json << 'EOF'
{
  "name": "test-workspace",
  "version": "1.0.0",
  "private": true
}
EOF

echo "[2/7] Starting container..."
docker run -d \
    --name spark-devcontainer-test \
    --cap-add=SYS_ADMIN \
    --device=/dev/fuse \
    --security-opt=apparmor:unconfined \
    -v /tmp/test-workspace:/workspace \
    -v /dev/fuse:/dev/fuse:rw \
    -w /workspace \
    --user vscode \
    "$DEVCONTAINER_IMAGE" \
    sleep infinity 2>&1 | tee "$LOG_DIR/docker-run.log"

# Wait for container to be running
echo "[3/7] Waiting for container to be ready..."
max_wait=30
elapsed=0
while [ $elapsed -lt $max_wait ]; do
    if [ "$(docker inspect spark-devcontainer-test --format='{{.State.Status}}' 2>/dev/null)" = "running" ]; then
        break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done

if [ $elapsed -ge $max_wait ]; then
    echo "ERROR: Container failed to start"
    docker logs spark-devcontainer-test 2>&1 | tee "$LOG_DIR/container-startup-failure.log"
    exit 1
fi

# Run post-create-commands.sh
echo "[4/7] Running post-create-commands.sh..."
docker exec spark-devcontainer-test bash -c "cd /workspace && /tmp/overlay/post-create-commands.sh" 2>&1 | tee "$LOG_DIR/post-create.log"
POST_CREATE_EXIT=$?

if [ $POST_CREATE_EXIT -ne 0 ]; then
    echo "ERROR: post-create-commands.sh failed with exit code $POST_CREATE_EXIT"
    exit 1
fi

# Run post-attach-commands.sh
echo "[5/7] Running post-attach-commands.sh..."
docker exec spark-devcontainer-test bash -c "cd /workspace && /tmp/overlay/post-attach-commands.sh" 2>&1 | tee "$LOG_DIR/post-attach.log"
POST_ATTACH_EXIT=$?

if [ $POST_ATTACH_EXIT -ne 0 ]; then
    echo "ERROR: post-attach-commands.sh failed with exit code $POST_ATTACH_EXIT"
    docker logs spark-devcontainer-test 2>&1 | tee "$LOG_DIR/container-logs-failure.log"
    exit 1
fi

# Test Spark Shell with SELECT 1
echo "[6/7] Testing Spark Shell..."
docker exec spark-devcontainer-test bash -c 'echo "spark.sql(\"SELECT 1\").show()" | /opt/spark/bin/spark-shell --master local[1] 2>&1' 2>&1 | tee "$LOG_DIR/spark-shell.log"
if grep -q "^\|  1\|$" "$LOG_DIR/spark-shell.log"; then
    echo "✓ Spark Shell test passed"
else
    echo "ERROR: Spark Shell test failed"
    exit 1
fi

# Test Livy health check
echo "[7/7] Testing Livy health check..."
max_retries=30
retry_count=0
LIVY_HEALTHY=false

while [ $retry_count -lt $max_retries ]; do
    if docker exec spark-devcontainer-test curl -s http://localhost:8998/sessions 2>&1 | tee "$LOG_DIR/livy-health.log" | grep -q "sessions"; then
        LIVY_HEALTHY=true
        break
    fi
    sleep 1
    retry_count=$((retry_count + 1))
done

if [ "$LIVY_HEALTHY" = true ]; then
    echo "✓ Livy health check passed"
else
    echo "ERROR: Livy health check failed"
    docker exec spark-devcontainer-test cat /workspace/logs/livy/livy-server.log 2>&1 | tee "$LOG_DIR/livy-server.log" || true
    exit 1
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ ALL TESTS PASSED"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Test logs saved to: $LOG_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
