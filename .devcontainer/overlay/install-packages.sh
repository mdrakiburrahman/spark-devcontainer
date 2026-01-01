#!/usr/bin/env -S bash -e

export ACCEPT_EULA=Y
export DEBIAN_FRONTEND=noninteractive
export OS_DISTRIBUTION=$(grep VERSION_ID /etc/os-release | cut -d '"' -f 2)

curl -sSL -O "https://packages.microsoft.com/config/ubuntu/${OS_DISTRIBUTION}/packages-microsoft-prod.deb"
sudo dpkg -i packages-microsoft-prod.deb >/dev/null
rm -f packages-microsoft-prod.deb

apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    cmake \
    cpio \
    curl \
    file \
    gnupg \
    jq \
    libc6 \
    lsb-release \
    msodbcsql18 \
    openjdk-17-jdk \
    openssl \
    p7zip-full \
    pkg-config \
    rpm2cpio \
    software-properties-common \
    unixodbc \
    unixodbc-dev \
    unzip \
    vim \
    wget

# Local spark version is dictated by available runtime in Azure Synapse and Fabric:
#
# - https://learn.microsoft.com/en-us/azure/synapse-analytics/spark/apache-spark-version-support#supported-azure-synapse-runtime-releases
#
SPARK_VERSION='3.5.1'
echo "Installing Apache Spark '$SPARK_VERSION' (for local 'spark-submit', identical to Azure Synapse runtime)"
wget https://archive.apache.org/dist/spark/spark-$SPARK_VERSION/spark-$SPARK_VERSION-bin-hadoop3.tgz &&
    tar -xvf spark-$SPARK_VERSION-bin-hadoop3.tgz &&
    mkdir -p /opt/spark &&
    mv spark-$SPARK_VERSION-bin-hadoop3/* /opt/spark &&
    rm -rf spark-$SPARK_VERSION-bin-hadoop3.tgz &&
    rm -rf spark-$SPARK_VERSION-bin-hadoop3

sudo apt-get autoremove -y &&
    sudo apt-get clean -y &&
    sudo rm -rf /var/lib/apt/lists/* &&
    sudo rm -rf /tmp/downloads
