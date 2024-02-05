#!/bin/bash

start_containers() {
  aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 636276102612.dkr.ecr.us-east-1.amazonaws.com

  export ECR_REGISTRY="636276102612.dkr.ecr.us-east-1.amazonaws.com"
  export ECR_REPOSITORY_MYSQL="mysql_image"
  export ECR_REPOSITORY_APP="app_image"
  export ECR_REPOSITORY_PROXY="proxy_image"
  
  echo "Starting user defined bridge network..." 
  docker network create custom_nw 2>/dev/null || true

  echo "Starting DB container..."
  DBID=$(docker run -d -p 3306:3306 -e MYSQL_ROOT_PASSWORD=pw --net custom_nw --name my_db $ECR_REGISTRY/$ECR_REPOSITORY_MYSQL)

  echo "Waiting for MySQL to be ready..."
  until docker exec $DBID mysqladmin ping -h"localhost" --silent; do
    echo -n "."
    sleep 10
  done
  echo "MySQL is up and running!"

  DBHOST=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $DBID)
  export DBHOST
  export DBPORT=3306

  echo "Starting webserver containers..."
  (docker run -p 8081:8080 -e DBHOST=$DBHOST -e DBPORT=$DBPORT -e APP_COLOR="blue" --net custom_nw -d --name app_blue $ECR_REGISTRY/$ECR_REPOSITORY_APP && echo "App1 started") &
  (docker run -p 8082:8080 -e DBHOST=$DBHOST -e DBPORT=$DBPORT -e APP_COLOR="pink" --net custom_nw -d --name app_pink $ECR_REGISTRY/$ECR_REPOSITORY_APP && echo "App2 started") &
  (docker run -p 8083:8080 -e DBHOST=$DBHOST -e DBPORT=$DBPORT -e APP_COLOR="lime" --net custom_nw -d --name app_lime $ECR_REGISTRY/$ECR_REPOSITORY_APP && echo "App3 started") &
  wait
  echo "All containers started!"

  echo "Starting reverse-proxy from port 8080 to containers..."
  docker build -t nginx-reverse-proxy -f Dockerfile_nginx .
  docker run -d -p 8080:80 -e DBHOST=$DBHOST -e DBPORT=$DBPORT --net custom_nw --name reverse-proxy $ECR_REGISTRY/$ECR_REPOSITORY_PROXY
}

stop_and_cleanup() {
  echo "Stopping and removing docker containers..."
  docker rm $(docker stop $(docker ps -a -q))

  echo "Deleting all docker images..."
  docker rmi -f $(docker images -q)

  echo "Deleting docker user network ..."
  docker network rm custom_nw
}

echo "Select an action:"
echo "1. Start containers"
echo "2. Delete containers, images and user network"
read -p "Enter your choice (1/2): " choice

case "$choice" in
  "1")
    start_containers
    ;;
  "2")
    stop_and_cleanup
    ;;
  *)
    echo "Invalid choice. Please select 1 or 2."
    exit 1
    ;;
esac

exit 0
