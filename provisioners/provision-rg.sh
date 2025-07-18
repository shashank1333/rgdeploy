#!/bin/bash
sudo mkdir -p "${RG_HOME}"
sudo mkdir -p "${RG_HOME}/logs"
sudo mkdir -p "${RG_HOME}/slogs"
sudo mkdir -p "${RG_HOME}/notification_sink_logs"
sudo mkdir -p "${RG_HOME}/config"
sudo mkdir -p "${RG_HOME}/integrations"
sudo mkdir -p "${RG_HOME}/topologies"
sudo mkdir -p "${RG_HOME}/catalog"
sudo cp ${RG_SRC}/nginx.conf  ${RG_HOME}
sudo echo -e "RG_HOME='/opt/deploy/sp2'\n" >> sudo /etc/environment
cd ${RG_SRC}
sudo tar -czf config.tar.gz config
sudo zip dump.zip dump/*
sudo docker swarm leave --force
sudo docker swarm init --default-addr-pool 172.20.0.0/16
