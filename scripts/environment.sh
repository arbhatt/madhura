#!/bin/bash

networkName='dataInsightNet'

zk='zookeeper'
zkPort=2181
zkImage='confluentinc/cp-zookeeper:5.1.0'

kafka='kafka'
kafkaPort=9092 
kafkaImage='confluentinc/cp-kafka:5.1.0'
replication=1

createNetwork() {
    networkName=$1
    dataInsightNetworkName=`docker network ls | grep $networkName | awk -F' ' {'print $2'}`

    if [ 'netw:'$dataInsightNetworkName == 'netw:' ];
    then
        docker network create $networkName
        echo Network dataInsightNet created    
    else
        echo Network dataInsightNet already exists
    fi
    docker network inspect $networkName
}

removeNetwork() {
    networkname=$1
    docker network rm $networkName
}

startZookeeper() {
    name=$1
    port=$2
    image=$3
    networkName=$4
    echo Starting zookeeper
    docker run -d --net=$networkName --name=$name  -p $port:$port -e ZOOKEEPER_CLIENT_PORT=$port $image
    sleep 10
    echo started
}

stopContainer() {
    name=$1
    echo Stopping $name
    imageId=`docker stop $name`
    docker rm $imageId
    echo stopped
}

startKafka() {
    name=$1
    port=$2
    image=$3
    networkName=$4
    zkName=$5
    zkPort=$6
    replication=$7
    echo Starting kafka
    docker run -d --net=$networkName --name=$name  -p $port:$port -e KAFKA_ZOOKEEPER_CONNECT=$zkName:$zkPort -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://$name:$port -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=$replication $image
    sleep 10
    echo started
}

stopAll() {
    
    stopContainer kibana
    stopContainer elasticsearch

    # stopContainer control-center
    # stopContainer kafka-rest
    # stopContainer $kafka
    # stopContainer $zk
    removeNetwork $networkName
}

startAll() {
    createNetwork $networkName
    # startZookeeper $zk $zkPort $zkImage $networkName
    # startKafka $kafka $kafkaPort $kafkaImage $networkName $zk $zkPort $replication    
    # startKafkaRestProxy kafka-rest confluentinc/cp-kafka-rest:5.1.0 $networkName $zk $zkPort 
    # startControlCenter control-center $networkName 9021 $zk $zkPort $kafka $kafkaPort $replication confluentinc/cp-enterprise-control-center:5.1.0

    startElasticSearch elasticsearch $networkName 9200 9300 ~/madhura/data/elasticsearch docker.elastic.co/elasticsearch/elasticsearch:6.5.4
    startKibana kibana $networkName 5601 docker.elastic.co/kibana/kibana:6.5.4
}

startKafkaRestProxy() {
    name=$1
    image=$2
    networkName=$3
    zkName=$4
    zkPort=$5
    echo Starting $name
    docker run -d --net=$networkName --name=$name -e KAFKA_REST_ZOOKEEPER_CONNECT=$zkName:$zkPort -e KAFKA_REST_LISTENERS=http://0.0.0.0:8082 -e KAFKA_REST_SCHEMA_REGISTRY_URL=http://schema-registry:8081 -e KAFKA_REST_HOST_NAME=$name $image
    echo started
}

startControlCenter() {
    name=$1
    networkName=$2
    port=$3
    zkName=$4
    zkPort=$5
    kafka=$6
    kafkaPort=$7
    replication=$8
    partitions=1
    threads=2
    image=$9

    echo Starting $name

    docker run -d \
        --name=$name \
        --net=$networkName \
        --ulimit nofile=16384:16384 \
        -p $port:$port \
        -e CONTROL_CENTER_ZOOKEEPER_CONNECT=$zkName:$zkPort \
        -e CONTROL_CENTER_BOOTSTRAP_SERVERS=$kafka:$kafkaPort \
        -e CONTROL_CENTER_REPLICATION_FACTOR=$replication \
        -e CONTROL_CENTER_MONITORING_INTERCEPTOR_TOPIC_PARTITIONS=$partitions \
        -e CONTROL_CENTER_INTERNAL_TOPICS_PARTITIONS=$partitions \
        -e CONTROL_CENTER_STREAMS_NUM_STREAM_THREADS=$threads \
        -e CONTROL_CENTER_CONNECT_CLUSTER=http://kafka-connect:8082 \
        $image
    echo started
}

startLogstash() {
    name=$1
    networkName=$2
    pipelineDir=$3
    logsDir=$4
    dataDir=$5
    image=$6
    docker run --rm -it --name=$name --net=$networkName -v $pipelineDir:/usr/share/logstash/pipeline -v $logsDir:/usr/share/logstash/logs -v $dataDir:/usr/share/logstash/data -e xpack.monitoring.enabled=false $image
}

startElasticSearch() {
    name=$1
    networkName=$2
    port=$3
    adminPort=$4
    dataDir=$5
    image=$6

echo ******* $dataDir 
    echo Starting $name
    docker run -d --name=$name --net=$networkName -p $port:$port -p $adminPort:$adminPort \
        -e "discovery.type=single-node" \
        -e "xpack.security.enabled=false" \
        -e "xpack.monitoring.enabled=false" \
        -e "xpack.ml.enabled=false" \
        -e "xpack.graph.enabled=false" \
        -e "xpack.watcher.enabled=false" \
        -e "path.data=$dataDir/esData" \
        -e "path.logs=$dataDir/logs" \
        -v $dataDir/data:/usr/share/elasticsearch/data $image
    echo started
}

startKibana() {
    name=$1
    networkName=$2
    port=$3
    image=$4

    echo Starting $name
    docker run -d --name=$name --net=$networkName -p $port:$port $image
    echo started
}

## Main Method ##
startOrStop=$1

if [ 's'$startOrStop == 's' ];
then
    echo 'Usage: environment <start|stop|restart>'
    exit
fi

if [ $startOrStop == 'start' ];
then
    startAll
fi

if [ $startOrStop == 'stop' ];
then
    stopAll
fi

if [ $startOrStop == 'restart' ];
then
    stopAll
    startAll
fi

if [ $startOrStop == 'read' ];
then
    startLogstash logstash $networkName ~/madhura/scripts/logstash/conf ~/madhura/logs/logstash/ ~/madhura/data/logstash/ docker.elastic.co/logstash/logstash:6.5.4
fi

