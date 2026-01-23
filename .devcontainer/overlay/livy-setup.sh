#!/bin/bash -e

# ==============================================================================
# INSTALL - Add this to install-packages.sh
# ==============================================================================

install_livy() {
    LIVY_VERSION='0.9.0-incubating'
    SCALA_VERSION='2.12'
    LIVY_DOWNLOAD_URL="https://dist.apache.org/repos/dist/dev/incubator/livy/0.9.0-incubating-rc2"
    
    # Idempotency check - skip if already installed with correct version
    if [ -d "/opt/livy/bin" ] && [ -f "/opt/livy/bin/livy-server" ]; then
        # Check version by looking at jar files
        if ls /opt/livy/jars/livy-server-${LIVY_VERSION}.jar >/dev/null 2>&1; then
            echo "Apache Livy ${LIVY_VERSION} is already installed at /opt/livy"
            return 0
        else
            echo "Different Livy version found, upgrading to ${LIVY_VERSION}..."
            sudo rm -rf /opt/livy
        fi
    fi
    
    echo "Installing Apache Livy '$LIVY_VERSION' (Scala $SCALA_VERSION)"
    
    cd /tmp
    
    # Clean up any previous partial downloads
    rm -rf apache-livy-${LIVY_VERSION}_${SCALA_VERSION}-bin.zip apache-livy-${LIVY_VERSION}_${SCALA_VERSION}-bin 2>/dev/null || true
    
    wget "${LIVY_DOWNLOAD_URL}/apache-livy-${LIVY_VERSION}_${SCALA_VERSION}-bin.zip" || { echo "ERROR: Failed to download Livy"; return 1; }
    unzip apache-livy-${LIVY_VERSION}_${SCALA_VERSION}-bin.zip || { echo "ERROR: Failed to unzip Livy"; return 1; }
    sudo mkdir -p /opt/livy || { echo "ERROR: Failed to create /opt/livy"; return 1; }
    sudo mv apache-livy-${LIVY_VERSION}_${SCALA_VERSION}-bin/* /opt/livy || { echo "ERROR: Failed to move Livy files"; return 1; }
    sudo chown -R $(whoami):$(whoami) /opt/livy
    rm -rf apache-livy-${LIVY_VERSION}_${SCALA_VERSION}-bin.zip
    rm -rf apache-livy-${LIVY_VERSION}_${SCALA_VERSION}-bin
    
    # Create default configuration for local mode (idempotent)
    configure_livy
    
    echo "Apache Livy ${LIVY_VERSION} installed successfully!"
}

# ==============================================================================
# CONFIGURE - Create Livy configuration for local mode
# ==============================================================================

configure_livy() {
    local LIVY_CONF="/opt/livy/conf/livy.conf"
    
    # Idempotency check - skip if config exists
    if [ -f "$LIVY_CONF" ]; then
        echo "Livy configuration already exists at $LIVY_CONF"
        return 0
    fi
    
    echo "Creating Livy configuration for local mode..."
    
    cat > "$LIVY_CONF" << 'EOF'
# Livy configuration for local dev container with Spark 3.x
livy.spark.master = local[*]
livy.spark.deploy-mode = client
livy.file.local-dir-whitelist = /
livy.server.session.timeout = 1h
livy.repl.enable-hive-context = false
EOF
    
    echo "Livy configuration created at $LIVY_CONF"
}

# ==============================================================================
# START - Idempotent startup (add to post-attach-commands.sh)
# ==============================================================================

stop_livy() {
    export LIVY_HOME=/opt/livy
    
    echo "Stopping Apache Livy..."
    
    if pgrep -f "livy.server.LivyServer" >/dev/null; then
        $LIVY_HOME/bin/livy-server stop 2>/dev/null || true
        sleep 2
        # Force kill if still running
        pkill -f "livy.server.LivyServer" 2>/dev/null || true
        echo "Livy Server stopped"
    else
        echo "Livy Server is not running"
    fi
}

start_livy() {
    export SPARK_HOME=/opt/spark
    export LIVY_HOME=/opt/livy
    export JAVA_HOME=${JAVA_HOME:-/usr/lib/jvm/java-17-openjdk-amd64}

    echo "Starting Apache Livy..."

    # Check if Livy is installed
    if [ ! -f "$LIVY_HOME/bin/livy-server" ]; then
        echo "ERROR: Livy is not installed. Run install_livy first."
        return 1
    fi

    if pgrep -f "livy.server.LivyServer" >/dev/null; then
        echo "Livy Server already running"
    else
        echo "Livy is not running. Starting..."
        $LIVY_HOME/bin/livy-server start

        echo "Waiting for Livy to be ready..."
        local retries=0
        local max_retries=30
        until curl -s http://localhost:8998/sessions >/dev/null 2>&1; do
            sleep 2
            retries=$((retries + 1))
            if [ $retries -ge $max_retries ]; then
                echo "ERROR: Livy failed to start within timeout"
                return 1
            fi
        done
        echo "Livy is ready!"
    fi

    echo
    echo "----------------------------------"
    echo "Livy UI:    http://localhost:8998"
    echo "----------------------------------"
}

# ==============================================================================
# CALL - Create session and execute SQL
# NOTE: Interactive sessions (kind: sql/spark/pyspark) have compatibility issues
#       with Spark 3.x. Batch mode works reliably.
# ==============================================================================

LIVY_URL="http://localhost:8998"

create_session() {
    local KIND="${1:-spark}"  # Default to spark, can also use pyspark
    
    echo "Creating Livy $KIND session..."
    RESPONSE=$(curl -s -X POST "${LIVY_URL}/sessions" \
        -H "Content-Type: application/json" \
        -d "{\"kind\": \"$KIND\"}")

    SESSION_ID=$(echo "$RESPONSE" | jq -r '.id')
    
    if [ "$SESSION_ID" = "null" ] || [ -z "$SESSION_ID" ]; then
        echo "ERROR: Failed to create session"
        echo "$RESPONSE" | jq .
        return 1
    fi
    
    echo "Session ID: $SESSION_ID"

    # Wait for session to be ready
    echo "Waiting for session to be idle..."
    local retries=0
    local max_retries=60
    while true; do
        STATE=$(curl -s "${LIVY_URL}/sessions/${SESSION_ID}" | jq -r '.state')
        echo "  Session state: $STATE"
        if [ "$STATE" = "idle" ]; then
            break
        elif [ "$STATE" = "dead" ] || [ "$STATE" = "error" ]; then
            echo "Session failed to start!"
            echo "Check logs: curl -s ${LIVY_URL}/sessions/${SESSION_ID}/log | jq '.log[]'"
            return 1
        fi
        sleep 2
        retries=$((retries + 1))
        if [ $retries -ge $max_retries ]; then
            echo "ERROR: Session creation timed out"
            return 1
        fi
    done

    echo "Session $SESSION_ID is ready!"
    echo "$SESSION_ID"
}

execute_code() {
    local SESSION_ID="$1"
    local CODE="$2"

    if [ -z "$SESSION_ID" ] || [ -z "$CODE" ]; then
        echo "Usage: execute_code <session_id> <code>"
        return 1
    fi

    echo "Executing code on session $SESSION_ID..."

    # Escape the code for JSON
    local ESCAPED_CODE=$(echo "$CODE" | jq -Rs .)
    
    RESPONSE=$(curl -s -X POST "${LIVY_URL}/sessions/${SESSION_ID}/statements" \
        -H "Content-Type: application/json" \
        -d "{\"code\": $ESCAPED_CODE}")

    STATEMENT_ID=$(echo "$RESPONSE" | jq -r '.id')
    
    if [ "$STATEMENT_ID" = "null" ] || [ -z "$STATEMENT_ID" ]; then
        echo "ERROR: Failed to submit statement"
        echo "$RESPONSE" | jq .
        return 1
    fi

    echo "Statement ID: $STATEMENT_ID"

    # Poll for result
    local retries=0
    local max_retries=120
    while true; do
        RESULT=$(curl -s "${LIVY_URL}/sessions/${SESSION_ID}/statements/${STATEMENT_ID}")
        STATE=$(echo "$RESULT" | jq -r '.state')

        if [ "$STATE" = "available" ]; then
            echo "Output:"
            echo "$RESULT" | jq '.output'
            break
        elif [ "$STATE" = "error" ] || [ "$STATE" = "cancelled" ]; then
            echo "Statement failed!"
            echo "$RESULT" | jq '.output'
            return 1
        fi
        sleep 1
        retries=$((retries + 1))
        if [ $retries -ge $max_retries ]; then
            echo "ERROR: Statement execution timed out"
            return 1
        fi
    done
}

# Alias for backward compatibility
execute_sql() {
    execute_code "$@"
}

# ==============================================================================
# KILL SESSION - Delete a Livy session
# ==============================================================================

kill_session() {
    local SESSION_ID="$1"
    
    if [ -z "$SESSION_ID" ]; then
        echo "Usage: kill_session <session_id>"
        echo "List sessions: curl -s ${LIVY_URL}/sessions | jq '.sessions[] | {id, state}'"
        return 1
    fi
    
    echo "Killing session $SESSION_ID..."
    
    RESPONSE=$(curl -s -X DELETE "${LIVY_URL}/sessions/${SESSION_ID}")
    
    if [ -z "$RESPONSE" ] || [ "$RESPONSE" = "null" ]; then
        echo "Session $SESSION_ID deleted successfully"
        return 0
    else
        echo "Response: $RESPONSE"
        return 0
    fi
}

kill_all_sessions() {
    echo "Killing all Livy sessions..."
    
    SESSION_IDS=$(curl -s "${LIVY_URL}/sessions" | jq -r '.sessions[].id')
    
    if [ -z "$SESSION_IDS" ]; then
        echo "No active sessions found"
        return 0
    fi
    
    for sid in $SESSION_IDS; do
        kill_session "$sid"
    done
    
    echo "All sessions killed"
}

# ==============================================================================
# EXAMPLE USAGE (uncomment to run)
# ==============================================================================

# install_livy
# start_livy
# SESSION_ID=$(create_session spark | tail -1)
# execute_code "$SESSION_ID" 'spark.sql("SELECT 1 as test").show()'
# kill_session "$SESSION_ID"
# kill_all_sessions
