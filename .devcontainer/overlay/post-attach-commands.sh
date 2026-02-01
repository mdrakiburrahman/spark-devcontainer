#!/bin/bash -e

export SPARK_HOME=/opt/spark
export LIVY_HOME=/opt/livy

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

USER_SPARK_DEFAULTS="${GIT_ROOT}/spark-defaults.conf"
USER_HIVE_SITE="${GIT_ROOT}/hive-site.xml"

SPARK_DEFAULTS="/opt/spark/conf/spark-defaults.conf"
HIVE_SITE="/opt/spark/conf/hive-site.xml"

if [ -z "$GIT_ROOT" ]; then
    echo "ERROR: Not inside a git repository. Cannot locate configuration files."
    exit 1
fi

if [ ! -f "$USER_HIVE_SITE" ]; then
    echo "ERROR: Required file not found: $USER_HIVE_SITE"
    echo "Please create hive-site.xml in your git root directory."
    exit 1
fi

if [ ! -f "$USER_SPARK_DEFAULTS" ]; then
    echo "ERROR: Required file not found: $USER_SPARK_DEFAULTS"
    echo "Please create spark-defaults.conf in your git root directory."
    exit 1
fi

echo "Found user hive-site.xml at $USER_HIVE_SITE"
sudo cp "$USER_HIVE_SITE" "$HIVE_SITE"

echo "Found user spark-defaults.conf at $USER_SPARK_DEFAULTS, moving to $SPARK_DEFAULTS"
sudo cp "$USER_SPARK_DEFAULTS" "$SPARK_DEFAULTS"

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