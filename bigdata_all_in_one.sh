#!/bin/bash

set -e

HADOOP_VERSION="3.4.1"
SPARK_VERSION="3.5.9"
ZOOKEEPER_VERSION="3.9.5"

JAVA_HOME=$(dirname $(dirname $(readlink -f $(which java))))

HADOOP_HOME="$HOME/hadoop"
SPARK_HOME="$HOME/spark"
ZOOKEEPER_HOME="$HOME/zookeeper"

echo "===== BIG DATA AUTO SETUP ====="

########################################
# Packages
########################################

sudo apt update
sudo apt install -y wget curl ssh rsync tar net-tools

########################################
# SSH
########################################

mkdir -p ~/.ssh

if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -P "" -f ~/.ssh/id_rsa
fi

touch ~/.ssh/authorized_keys
grep -q "$(cat ~/.ssh/id_rsa.pub)" ~/.ssh/authorized_keys || \
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

chmod 600 ~/.ssh/authorized_keys

sudo service ssh start || true

########################################
# Environment Variables
########################################

grep -q "BIGDATA_ENV_SETUP" ~/.bashrc || cat >> ~/.bashrc <<EOF

# BIGDATA_ENV_SETUP
export JAVA_HOME=$JAVA_HOME

export HADOOP_HOME=\$HOME/hadoop
export HADOOP_CONF_DIR=\$HADOOP_HOME/etc/hadoop

export SPARK_HOME=\$HOME/spark
export ZOOKEEPER_HOME=\$HOME/zookeeper

export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin
export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin
export PATH=\$PATH:\$ZOOKEEPER_HOME/bin
EOF

export JAVA_HOME="$JAVA_HOME"
export HADOOP_HOME="$HADOOP_HOME"
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
export SPARK_HOME="$SPARK_HOME"
export ZOOKEEPER_HOME="$ZOOKEEPER_HOME"

export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
export PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin
export PATH=$PATH:$ZOOKEEPER_HOME/bin

########################################
# Hadoop
########################################

if [ ! -d "$HADOOP_HOME/bin" ]; then

    cd /tmp

    wget -c \
    https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz

    tar -xzf hadoop-${HADOOP_VERSION}.tar.gz

    mv hadoop-${HADOOP_VERSION} "$HADOOP_HOME"

fi

mkdir -p ~/hadoopdata/hdfs/namenode
mkdir -p ~/hadoopdata/hdfs/datanode

echo "export JAVA_HOME=$JAVA_HOME" >> \
$HADOOP_HOME/etc/hadoop/hadoop-env.sh 2>/dev/null || true

cat > $HADOOP_HOME/etc/hadoop/core-site.xml <<EOF
<configuration>
 <property>
  <name>fs.defaultFS</name>
  <value>hdfs://localhost:9000</value>
 </property>
</configuration>
EOF

cat > $HADOOP_HOME/etc/hadoop/hdfs-site.xml <<EOF
<configuration>
 <property>
  <name>dfs.replication</name>
  <value>1</value>
 </property>

 <property>
  <name>dfs.namenode.name.dir</name>
  <value>file:///home/$USER/hadoopdata/hdfs/namenode</value>
 </property>

 <property>
  <name>dfs.datanode.data.dir</name>
  <value>file:///home/$USER/hadoopdata/hdfs/datanode</value>
 </property>
</configuration>
EOF

cat > $HADOOP_HOME/etc/hadoop/mapred-site.xml <<EOF
<configuration>
 <property>
  <name>mapreduce.framework.name</name>
  <value>yarn</value>
 </property>
</configuration>
EOF

cat > $HADOOP_HOME/etc/hadoop/yarn-site.xml <<EOF
<configuration>
 <property>
  <name>yarn.nodemanager.aux-services</name>
  <value>mapreduce_shuffle</value>
 </property>
</configuration>
EOF

if [ ! -d ~/hadoopdata/hdfs/namenode/current ]; then
    hdfs namenode -format -force
fi

########################################
# Start Hadoop
########################################

jps | grep -q NameNode || start-dfs.sh || true
jps | grep -q ResourceManager || start-yarn.sh || true

########################################
# ZooKeeper
########################################

if [ ! -d "$ZOOKEEPER_HOME" ]; then

    cd /tmp

    wget -c \
    https://downloads.apache.org/zookeeper/zookeeper-${ZOOKEEPER_VERSION}/apache-zookeeper-${ZOOKEEPER_VERSION}-bin.tar.gz

    tar -xzf apache-zookeeper-${ZOOKEEPER_VERSION}-bin.tar.gz

    mv apache-zookeeper-${ZOOKEEPER_VERSION}-bin \
       "$ZOOKEEPER_HOME"

fi

if [ ! -f "$ZOOKEEPER_HOME/conf/zoo.cfg" ]; then

    cp \
    "$ZOOKEEPER_HOME/conf/zoo_sample.cfg" \
    "$ZOOKEEPER_HOME/conf/zoo.cfg"

fi

mkdir -p "$ZOOKEEPER_HOME/data"

grep -q "^dataDir=" \
"$ZOOKEEPER_HOME/conf/zoo.cfg" || \
echo "dataDir=$ZOOKEEPER_HOME/data" >> \
"$ZOOKEEPER_HOME/conf/zoo.cfg"

jps | grep -q QuorumPeerMain || zkServer.sh start || true

########################################
# Spark
########################################

if [ ! -d "$SPARK_HOME" ]; then

    cd /tmp

    wget -c \
    https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz

    tar -xzf spark-${SPARK_VERSION}-bin-hadoop3.tgz

    mv spark-${SPARK_VERSION}-bin-hadoop3 \
       "$SPARK_HOME"

fi

########################################
# Start Spark
########################################

jps | grep -q Master || start-master.sh || true

sleep 5

MASTER_URL=$(jps | grep -q Master && echo "spark://localhost:7077")

jps | grep -q Worker || \
start-worker.sh $MASTER_URL || true

########################################
# Verification
########################################

echo
echo "===== INSTALLED SERVICES ====="

java --version || true
echo

hadoop version || true
echo

spark-submit --version || true
echo

zkServer.sh status || true
echo

echo "===== JPS ====="
jps

echo
echo "HDFS UI  : http://localhost:9870"
echo "YARN UI  : http://localhost:8088"
echo "SPARK UI : http://localhost:8080"
