#!/bin/bash -e

export SPARK_HOME=/opt/spark
export LIVY_HOME=/opt/livy

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
USER_SPARK_DEFAULTS="${GIT_ROOT}/spark-defaults.conf"
SPARK_DEFAULTS="/opt/spark/conf/spark-defaults.conf"

# Function to append lines that don't already exist in destination
append_if_missing() {
    local src="$1"
    local dest="$2"
    while IFS= read -r line || [ -n "$line" ]; do
        if [ -n "$line" ] && ! grep -qxF "$line" "$dest" 2>/dev/null; then
            echo "$line" >> "$dest"
        fi
    done < "$src"
}

if [ -n "$GIT_ROOT" ] && [ -f "$USER_SPARK_DEFAULTS" ]; then
    echo "Found user spark-defaults.conf at $USER_SPARK_DEFAULTS"
    append_if_missing "$USER_SPARK_DEFAULTS" "$SPARK_DEFAULTS"
else
    echo "Applying default spark-defaults.conf"
    TEMP_DEFAULTS=$(mktemp)
    cat > "$TEMP_DEFAULTS" << 'EOF'
spark.databricks.delta.schema.autoMerge.enabled=true
spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog
spark.sql.catalogImplementation=hive
spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension
spark.sql.sources.default=delta
EOF
    append_if_missing "$TEMP_DEFAULTS" "$SPARK_DEFAULTS"
    rm -f "$TEMP_DEFAULTS"
fi

echo "Starting Apache Spark..."

if pgrep -f "org.apache.spark.deploy.master.Master" >/dev/null; then
    echo "Spark Master already running"
else
    echo "Spark is not running. Starting..."
    sudo /opt/spark/sbin/start-master.sh
fi

if pgrep -f "org.apache.spark.deploy.worker.Worker" >/dev/null; then
    echo "Spark Worker already running"
else
    echo "Spark Worker is not running. Starting..."
    sudo /opt/spark/sbin/start-worker.sh spark://$(hostname):7077
fi

if pgrep -f "livy.server.LivyServer" >/dev/null; then
        echo "Livy Server already running"
    else
        echo "Livy is not running. Starting..."
        $LIVY_HOME/bin/livy-server start

        echo "Waiting for Livy to be ready..."
        retries=0
        max_retries=30
        until curl -s http://localhost:8998/sessions >/dev/null 2>&1; do
            sleep 2
            retries=$((retries + 1))
            if [ $retries -ge $max_retries ]; then
                echo "ERROR: Livy failed to start within timeout"
                break
            fi
        done
        if [ $retries -lt $max_retries ]; then
            echo "Livy is ready!"
        fi
    fi

echo
echo "----------------------------------"
echo "Master UI:  http://localhost:8080"
echo "Workers UI: http://localhost:8081"
echo "Livy UI:    http://localhost:8998"
echo "----------------------------------"

echo
echo "Post-Attach Commands Complete!"
echo