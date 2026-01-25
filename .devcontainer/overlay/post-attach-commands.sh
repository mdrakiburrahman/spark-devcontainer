#!/bin/bash -e

export SPARK_HOME=/opt/spark
export LIVY_HOME=/opt/livy

GIT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")

# User-configurable paths (place these files in your git root to customize)
USER_SPARK_DEFAULTS="${GIT_ROOT}/spark-defaults.conf"
USER_HIVE_SITE="${GIT_ROOT}/hive-site.xml"

# Target locations
SPARK_DEFAULTS="/opt/spark/conf/spark-defaults.conf"
HIVE_SITE="/opt/spark/conf/hive-site.xml"

# Default metastore/warehouse locations (used when no user config provided)
DEFAULT_METASTORE_DIR="${GIT_ROOT}/.spark/metastore"
DEFAULT_WAREHOUSE_DIR="${GIT_ROOT}/.spark/warehouse"

# Ensure metastore and warehouse directories exist
setup_default_directories() {
    mkdir -p "$DEFAULT_METASTORE_DIR"
    mkdir -p "$DEFAULT_WAREHOUSE_DIR"
    chmod 777 "$DEFAULT_METASTORE_DIR"
    chmod 777 "$DEFAULT_WAREHOUSE_DIR"
}

# Configure hive-site.xml (Hive metastore settings)
#
if [ -n "$GIT_ROOT" ] && [ -f "$USER_HIVE_SITE" ]; then
    echo "Found user hive-site.xml at $USER_HIVE_SITE"
    sudo cp "$USER_HIVE_SITE" "$HIVE_SITE"
else
    echo "Applying default hive-site.xml (metastore at $DEFAULT_METASTORE_DIR)"
    setup_default_directories
    sudo tee "$HIVE_SITE" > /dev/null << EOF
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
  <!-- Derby metastore connection - shared across all sessions -->
  <property>
    <name>javax.jdo.option.ConnectionDriverName</name>
    <value>org.apache.derby.jdbc.EmbeddedDriver</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionURL</name>
    <value>jdbc:derby:${DEFAULT_METASTORE_DIR}/metastore_db;create=true</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionUserName</name>
    <value>APP</value>
  </property>
  <property>
    <name>javax.jdo.option.ConnectionPassword</name>
    <value>mine</value>
  </property>
  <!-- Default warehouse location -->
  <property>
    <name>hive.metastore.warehouse.dir</name>
    <value>${DEFAULT_WAREHOUSE_DIR}</value>
  </property>
  <!-- Schema initialization -->
  <property>
    <name>datanucleus.schema.autoCreateAll</name>
    <value>true</value>
  </property>
  <property>
    <name>hive.metastore.schema.verification</name>
    <value>false</value>
  </property>
</configuration>
EOF
fi

# Configure spark-defaults.conf (Spark session settings)
#
if [ -n "$GIT_ROOT" ] && [ -f "$USER_SPARK_DEFAULTS" ]; then
    echo "Found user spark-defaults.conf at $USER_SPARK_DEFAULTS, moving to $SPARK_DEFAULTS"
    sudo cp "$USER_SPARK_DEFAULTS" "$SPARK_DEFAULTS"
else
    echo "Applying default spark-defaults.conf (warehouse at $DEFAULT_WAREHOUSE_DIR)"
    setup_default_directories
    sudo tee "$SPARK_DEFAULTS" > /dev/null << EOF
# Catalog configuration
spark.sql.catalogImplementation=hive
spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog
spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension
spark.sql.sources.default=delta

# Delta schema options
spark.databricks.delta.schema.autoMerge.enabled=true

# Warehouse location
spark.sql.warehouse.dir=${DEFAULT_WAREHOUSE_DIR}

# Derby metastore location
spark.driver.extraJavaOptions=-Dderby.system.home=${DEFAULT_METASTORE_DIR}
EOF
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