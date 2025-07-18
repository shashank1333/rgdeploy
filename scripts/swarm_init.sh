#!/bin/bash

# Get the host machine's primary IP address
host_ip=$(ip route get 1 | awk '{print $(NF-2); exit}')

# Extract the first octet to determine IP range
ip_prefix=$(echo "$host_ip" | cut -d. -f1)

# Choose a default address pool that doesn't clash
if [[ "$ip_prefix" == "10" ]]; then
    docker_subnet="172.20.0.0/16"
elif [[ "$ip_prefix" == "172" ]]; then
    docker_subnet="192.168.0.0/16"
elif [[ "$ip_prefix" == "192" ]]; then
    docker_subnet="10.10.0.0/16"
else
    # Fallback default
    docker_subnet="172.25.0.0/16"
fi

# Initialize Docker Swarm with the default address pool
docker swarm init --default-addr-pool "$docker_subnet" --default-addr-pool-mask-length 24

echo "Docker Swarm initialized with default address pool: $docker_subnet"
