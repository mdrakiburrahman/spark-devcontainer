#!/bin/bash -e

# ==============================================================================
# INSTALL - Add this to install-packages.sh
# ==============================================================================

install_livy() {
    LIVY_VERSION='0.8.0-incubating'
    echo "Installing Apache Livy '$LIVY_VERSION'"
    wget https://archive.apache.org/dist/incubator/livy/$LIVY_VERSION/apache-livy-$LIVY_VERSION-bin.zip &&
        unzip apache-livy-$LIVY_VERSION-bin.zip &&
        mkdir -p /opt/livy &&
        mv apache-livy-$LIVY_VERSION-bin/* /opt/livy &&
        rm -rf apache-livy-$LIVY_VERSION-bin.zip &&
        rm -rf apache-livy-$LIVY_VERSION-bin
}

# ==============================================================================
# START - Idempotent startup (add to post-attach-commands.sh)
# ==============================================================================

start_livy() {
    export SPARK_HOME=/opt/spark
    export LIVY_HOME=/opt/livy
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

    echo "Starting Apache Livy..."

    if pgrep -f "livy.server.LivyServer" >/dev/null; then
        echo "Livy Server already running"
    else
        echo "Livy is not running. Starting..."
        $LIVY_HOME/bin/livy-server start

        echo "Waiting for Livy to be ready..."
        until curl -s http://localhost:8998/sessions >/dev/null 2>&1; do
            sleep 2
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
# ==============================================================================

LIVY_URL="http://localhost:8998"

create_session() {
    echo "Creating Livy SQL session..."
    RESPONSE=$(curl -s -X POST "${LIVY_URL}/sessions" \
        -H "Content-Type: application/json" \
        -d '{"kind": "sql"}')

    SESSION_ID=$(echo "$RESPONSE" | jq -r '.id')
    echo "Session ID: $SESSION_ID"

    # Wait for session to be ready
    echo "Waiting for session to be idle..."
    while true; do
        STATE=$(curl -s "${LIVY_URL}/sessions/${SESSION_ID}" | jq -r '.state')
        echo "  Session state: $STATE"
        if [ "$STATE" = "idle" ]; then
            break
        elif [ "$STATE" = "dead" ] || [ "$STATE" = "error" ]; then
            echo "Session failed to start!"
            return 1
        fi
        sleep 2
    done

    echo "Session $SESSION_ID is ready!"
    echo "$SESSION_ID"
}

execute_sql() {
    local SESSION_ID="$1"
    local SQL_CODE="$2"

    echo "Executing: $SQL_CODE"

    RESPONSE=$(curl -s -X POST "${LIVY_URL}/sessions/${SESSION_ID}/statements" \
        -H "Content-Type: application/json" \
        -d "{\"code\": \"$SQL_CODE\", \"kind\": \"sql\"}")

    STATEMENT_ID=$(echo "$RESPONSE" | jq -r '.id')

    # Poll for result
    while true; do
        RESULT=$(curl -s "${LIVY_URL}/sessions/${SESSION_ID}/statements/${STATEMENT_ID}")
        STATE=$(echo "$RESULT" | jq -r '.state')

        if [ "$STATE" = "available" ]; then
            echo "$RESULT" | jq '.output'
            break
        elif [ "$STATE" = "error" ] || [ "$STATE" = "cancelled" ]; then
            echo "Statement failed!"
            echo "$RESULT" | jq '.output'
            break
        fi
        sleep 1
    done
}

# ==============================================================================
# EXAMPLE USAGE (uncomment to run)
# ==============================================================================

# install_livy
# start_livy
# SESSION_ID=$(create_session | tail -1)
# execute_sql "$SESSION_ID" "SELECT 1"
