#!/bin/bash

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

docker compose up -d

. "$SCRIPT_DIR"/../.env

wait_for_mongo() {
    local srvName=$1
    local port=$2
    local max_attempts=30
    local attempt=0

    echo "Waiting for MongoDB ($srvName) on port $port..."
    until docker exec -it "mongodb_${srvName}" mongosh --port "${port}" --eval "db.version()" &> /dev/null
    do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "MongoDB on port $port not ready after $max_attempts attempts, exiting..."
            exit 1
        fi
        sleep 2
    done
    echo "MongoDB on port $port is ready!"
}

wait_for_mongo shard1 "$SHARD_PORT"
wait_for_mongo shard2 "$SHARD_PORT"
wait_for_mongo config1 "$CONFIG_PORT"

echo "Initializing config replica set..."
docker compose exec -T mongodb_config1 mongosh --port "$CONFIG_PORT" --quiet <<EOF
rs.initiate(
  {
    _id: "configrs",
    configsvr: true,
    members: [{ _id: 0, host: "mongodb_config1:$CONFIG_PORT" }]
  }
)
EOF

echo "Initializing shard1 replica set..."
docker compose exec -T mongodb_shard1 mongosh --port "$SHARD_PORT" --quiet <<EOF
rs.initiate(
  {
    _id: "shard1rs",
    members: [{ _id: 0, host: "mongodb_shard1:$SHARD_PORT" }]
  }
)
EOF

echo "Initializing shard2 replica set..."
docker compose exec -T mongodb_shard2 mongosh --port "$SHARD_PORT" --quiet <<EOF
rs.initiate(
  {
    _id: "shard2rs",
    members: [{ _id: 0, host: "mongodb_shard2:$SHARD_PORT" }]
  }
)
EOF

wait_for_mongo router "$ROUTER_PORT"

echo "Adding shards to cluster..."
docker compose exec -T mongodb_router mongosh --port "$ROUTER_PORT" --quiet <<EOF
sh.addShard("shard1rs/mongodb_shard1:$SHARD_PORT");
sh.addShard("shard2rs/mongodb_shard2:$SHARD_PORT");
EOF

echo "Enabling sharding for database..."
docker compose exec -T mongodb_router mongosh --port "$ROUTER_PORT" --quiet <<EOF
sh.enableSharding("somedb");
EOF

echo "Sharding collection..."
docker compose exec -T mongodb_router mongosh --port "$ROUTER_PORT" --quiet <<EOF
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" });
EOF

echo "Fill test data..."
docker compose exec -T mongodb_router mongosh --port "$ROUTER_PORT" --quiet <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i});
EOF

echo "Cluster status:"
docker exec -it mongodb_router mongosh --eval 'sh.status()'
