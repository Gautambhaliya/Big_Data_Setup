#!/bin/bash

set -e

echo "========================================="
echo " BIG DATA AUTO INSTALL SCRIPT"
echo " Java 21 + Hadoop + Spark + ZooKeeper"
echo "========================================="

sudo apt update
sudo apt upgrade -y

echo "Installing required packages..."
sudo apt install -y \
openjdk-21-jdk \
ssh \
rsync \
wget \
curl \
tar \
vim \
net-tools

echo "Installing SSH..."

if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -P "" -f ~/.ssh/id_rsa
fi

cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

sudo service ssh start

echo "Checking Java..."
java -version

mkdir -p ~/downloads
cd ~/downloads

###################################################
# HADOOP
###################################################

HADOOP_VERSION=3.4.1

if [ ! -d ~/hadoop ]; then
    wget https://downloads.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz

    tar -xzf hadoop-${HADOOP_VERSION}.tar.gz

    mv hadoop-${HADOOP_VERSION} ~/hadoop
fi

###################################################
# SPARK
###################################################

SPARK_VERSION=4.0.1

if [ ! -d ~/spark ]; then
    wget https://downloads.apache.org/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop3.tgz

    tar -xzf spark-${SPARK_VERSION}-bin-hadoop3.tgz

    mv spark-${SPARK_VERSION}-bin-hadoop3 ~/spark
fi

###################################################
# ZOOKEEPER
###################################################

ZK_VERSION=3.9.3

if [ ! -d ~/zookeeper ]; then
    wget https://downloads.apache.org/zookeeper/zookeeper-${ZK_VERSION}/apache-zookeeper-${ZK_VERSION}-bin.tar.gz

    tar -xzf apache-zookeeper-${ZK_VERSION}-bin.tar.gz

    mv apache-zookeeper-${ZK_VERSION}-bin ~/zookeeper
fi

###################################################
# ENVIRONMENT VARIABLES
###################################################

echo "Configuring environment variables..."

grep -q "HADOOP_HOME" ~/.bashrc || cat <<EOF >> ~/.bashrc

# JAVA
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export PATH=\$PATH:\$JAVA_HOME/bin

# HADOOP
export HADOOP_HOME=\$HOME/hadoop
export HADOOP_CONF_DIR=\$HADOOP_HOME/etc/hadoop
export PATH=\$PATH:\$HADOOP_HOME/bin:\$HADOOP_HOME/sbin

# SPARK
export SPARK_HOME=\$HOME/spark
export PATH=\$PATH:\$SPARK_HOME/bin:\$SPARK_HOME/sbin

# ZOOKEEPER
export ZOOKEEPER_HOME=\$HOME/zookeeper
export PATH=\$PATH:\$ZOOKEEPER_HOME/bin
EOF

source ~/.bashrc

###################################################
# HADOOP DIRECTORIES
###################################################

mkdir -p ~/hadoopdata/hdfs/namenode
mkdir -p ~/hadoopdata/hdfs/datanode

###################################################
# HADOOP ENV
###################################################

sed -i '/JAVA_HOME/d' \
$HADOOP_HOME/etc/hadoop/hadoop-env.sh

echo 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64' \
>> $HADOOP_HOME/etc/hadoop/hadoop-env.sh

###################################################
# core-site.xml
###################################################

cat > $HADOOP_HOME/etc/hadoop/core-site.xml <<EOF
<configuration>
 <property>
  <name>fs.defaultFS</name>
  <value>hdfs://localhost:9000</value>
 </property>
</configuration>
EOF

###################################################
# hdfs-site.xml
###################################################

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

###################################################
# mapred-site.xml
###################################################

cp \
$HADOOP_HOME/etc/hadoop/mapred-site.xml.template \
$HADOOP_HOME/etc/hadoop/mapred-site.xml

cat > $HADOOP_HOME/etc/hadoop/mapred-site.xml <<EOF
<configuration>
 <property>
  <name>mapreduce.framework.name</name>
  <value>yarn</value>
 </property>
</configuration>
EOF

###################################################
# yarn-site.xml
###################################################

cat > $HADOOP_HOME/etc/hadoop/yarn-site.xml <<EOF
<configuration>

 <property>
  <name>yarn.nodemanager.aux-services</name>
  <value>mapreduce_shuffle</value>
 </property>

</configuration>
EOF

###################################################
# FORMAT NAMENODE
###################################################

echo "Formatting NameNode..."

if [ ! -d ~/hadoopdata/hdfs/namenode/current ]; then
    hdfs namenode -format -force
fi

###################################################
# START HADOOP
###################################################

start-dfs.sh
start-yarn.sh

###################################################
# ZOOKEEPER CONFIG
###################################################

cp \
$ZOOKEEPER_HOME/conf/zoo_sample.cfg \
$ZOOKEEPER_HOME/conf/zoo.cfg

zkServer.sh start

###################################################
# VERIFY
###################################################

echo
echo "====================================="
echo "INSTALLATION COMPLETE"
echo "====================================="

java -version

hadoop version

spark-submit --version

jps

echo
echo "HDFS Web UI:"
echo "http://localhost:9870"

echo
echo "YARN Web UI:"
echo "http://localhost:8088"

echo
echo "ZooKeeper Started"
