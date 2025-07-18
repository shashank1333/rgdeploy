#!/bin/bash
version="0.1.7"
echo "Fixing DocumentDB....(fixdocdb.sh v$version)"

if [ "$1" == "-h" ] || [ $# -lt 5 ]; then
	echo "Usage: $(basename $0) db_name admin_password user_name user_password"
	echo '    Param 1: URL of the DocumentDB instance'
	echo '             e.g. myinstance.c912049703214.us-east-2.docdb.amazonaws.com'
	echo '    Param 2: Name of the DB you want to use for application user e.g. PROD-cc'
	echo '    Param 3: MasterUserName e.g. rgadmin'
	echo '    Param 4: MasterUserPassword e.g.  rgadmin123'
	echo '    Param 5: URL for SNS Callback'
	echo '             Will use public-host-name if not passed'
	echo '             e.g. https://myrg.example.com/'
	exit 0
fi

# If user is using DocumentDB, it also means we are not using local mongodb.
# So disable the mongod service

systemctl disable mongod
service mongod stop
# Fetch IMDSv2 session token
TOKEN=$(wget --method=PUT --header="X-aws-ec2-metadata-token-ttl-seconds: 21600" -qO- http://169.254.169.254/latest/api/token)
myip=$(wget --header="X-aws-ec2-metadata-token: $TOKEN" -qO- http://169.254.169.254/latest/meta-data/local-ipv4)
echo "Private IP of this machine is $myip"
mydocdburl=$1
mydbname=$2
mydbuser=$3
mydbuserpwd=$4
myurl=$5
[ -z "$RG_HOME" ] && RG_HOME='/opt/deploy/sp2'
echo "RG_HOME=$RG_HOME"
[ -z "$RG_SRC" ] && RG_SRC='/home/ubuntu'
echo "RG_SRC=$RG_SRC"
[ -z "$S3_SOURCE" ] && S3_SOURCE=rg-deployment-docs
echo "S3_SOURCE=$S3_SOURCE"

if [ -z "$myurl" ]; then
	if [ -z "$public_host_name" ]; then
		echo "ERROR: No RG URL passed. Instance does not have public hostname. One of the two is required. Not modifying configs."
		baseurl=''
	else
		baseurl="http://$public_host_name/"
	fi
else
	baseurl="$myurl/"
	snsprotocol=$(echo "$myurl" | sed -e 's/\(http.*:\/\/\).*/\1/' | sed -e 's/://' -e 's/\///g')
	if [ -z "$snsprotocol" ]; then
		echo "WARNING: No protocol specified for RG URL. Assuming http!"
		baseurl="http://$myurl/"
	fi
fi
echo "snsUrl will be set to $baseurl"

# Modify the database to create roles and configs
echo "Modifying database $1 to create defaults"
if [ ! -f "$RG_SRC/dump.tar.gz" ]; then
	echo "No seed DB in $RG_SRC."
else
	echo "Seed DB exists. Renaming"
	mv "$RG_SRC/dump.tar.gz" "$RG_SRC/dump.old.tar.gz"
fi
echo "Downloading new dump file..."
aws s3 cp s3://${S3_SOURCE}/dump.zip "$RG_SRC"
echo "Extracting seed data from dump file."
unzip -o "$RG_SRC/dump.zip" -d "$RG_SRC"
if [ ! "$(ls -A $RG_SRC/dump)" ]; then
	echo "Error: No files found in dump folder. Your database cannot be seeded."
else
	mongoimport --host "$mydocdburl:27017" --ssl \
		--sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd" \
		--db "${mydbname}" --collection=standardcatalogitems --jsonArray\
		"$RG_SRC/dump/standardcatalogitems.json"
	mongoimport --host "$mydocdburl:27017" --ssl \
		--sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd" \
		--db "${mydbname}" --collection=configs --jsonArray\
		"$RG_SRC/dump/configs.json"
	mongoimport --host "$mydocdburl:27017" --ssl \
		--sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd" \
		--db "${mydbname}" --collection=studies --jsonArray\
		"$RG_SRC/dump/studies.json"

fi

if [ -z "$baseurl" ]; then
	echo "WARNING: Base URL is not passed. Skipping snsUrl configuration in DB."
else
	mongo --ssl --host "$mydocdburl:27017" --sslCAFile "$RG_HOME/config/rds-combined-ca-bundle.pem" \
		--username "$mydbuser" --password "$mydbuserpwd" <<EOF
use $mydbname
db.configs.remove({"key":"snsUrl"});
db.configs.insert({"key":"snsUrl","value":"$baseurl"});
EOF
fi

# rootca="${RG_HOME}/config/rootCA.key"
# rlca="${RG_HOME}/config/RL-CA.pem"
# mongodbkey="${RG_HOME}/config/mongodb.key"
# mongodbcsr="${RG_HOME}/config/mongodb.csr"
# mongodbcrt="${RG_HOME}/config/mongodb.crt"
# echo "Creating mongodb.pem file"
# host_name="$(wget -q -O - http://169.254.169.254/latest/meta-data/local-hostname | sed -e 's/\..*//')"
# openssl genrsa -out "$rootca" 2048
# openssl req -x509 -new -nodes -key "$rootca" -sha256 -days 1024 -out "$rlca" -subj "/CN=."
# openssl genrsa -out "$mongodbkey" 2048
# openssl req -new -key "$mongodbkey" -out "$mongodbcsr" -subj "/CN=$host_name"
# openssl x509 -req -in "$mongodbcsr" -CA "$rlca" -CAkey "$rootca" -CAcreateserial -out "$mongodbcrt" -days 500 -sha256
# cat "$mongodbkey" "$mongodbcrt" >"$RG_HOME/config/mongodb.pem"

# echo "Modifying mongo-config.json file"
# mytemp=$(mktemp -d -p "${RG_HOME}/tmp" -t "config.old.XXX")
# echo "$mytemp"
# cp "${RG_HOME}/config/mongo-config.json" "$mytemp"
# jq -r ".db_ssl_enable=true" "$mytemp/mongo-config.json" |
# 	jq -r ".db_auth_enable=true" |
# 	jq -r ".db_documentdb_enable=true" |
# 	jq -r '.db_ssl_config.CAFile="rds-combined-ca-bundle.pem"' |
# 	jq -r '.db_ssl_config.PEMFile="mongodb.pem"' |
# 	jq -r ".db_auth_config.username=\"$mydbuser\"" |
# 	jq -r ".db_auth_config.password=\"$mydbuserpwd\"" |
# 	jq -r '.db_auth_config.authenticateDb="admin"' >"${RG_HOME}/config/mongo-config.json"

echo "Modifying docker-compose.yml file"
if [ -f "${RG_HOME}/docker-compose.yml" ]; then
	echo "docker-compose.yml exists"
	sed -i -e "s/DB_HOST=.*/DB_HOST=$mydocdburl/" "${RG_HOME}/docker-compose.yml"
	echo "Modified docker-compose.yml with DocumentDB instance URL"
fi
echo "Success"
