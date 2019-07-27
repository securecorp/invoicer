#!/usr/bin/env bash

# requires: pip install awscli awsebcli

# uncomment to debug
#set -x

fail() {
    echo configuration failed
    exit 1
}







dbsg="sg-0c4b9d0dc326496ba"
dbinstclass="db.t2.micro"
dbstorage=5
dbpass="tlzhq692900"
dbhost="jakeivcr201907242132.ce97vqlbgrwm.ap-northeast-2.rds.amazonaws.com"
dockerstack="64bit Amazon Linux 2018.03 v2.12.14 running Docker 18.06.1-ce"
identifier="jakeivcr201907242132"
aws elasticbeanstalk create-environment \
    --application-name $identifier \
    --environment-name $identifier-invoicer-api \
    --description "Invoicer API environment" \
    --tags "Key=Owner,Value=$(whoami)" \
    --solution-stack-name "$dockerstack" \
    --option-settings file://ebs-options.json \
    --tier "Name=WebServer,Type=Standard,Version=''" > tmp/$identifier/ebcreateapienv.json
echo "API environment $apieid is being created"

# grab the instance ID of the API environment, then its security group, and add that to the RDS security group
while true;
do
    aws elasticbeanstalk describe-environment-resources --environment-id $apieid > tmp/$identifier/ebapidesc.json || fail
    ec2id=$(jq -r '.EnvironmentResources.Instances[0].Id' tmp/$identifier/ebapidesc.json)
    if [ "$ec2id" != "null" ]; then break; fi
    echo -n '.'
    sleep 10
done
echo
aws ec2 describe-instances --instance-ids $ec2id > tmp/$identifier/${ec2id}.json || fail
sgid=$(jq -r '.Reservations[0].Instances[0].SecurityGroups[0].GroupId' tmp/$identifier/${ec2id}.json)
aws ec2 authorize-security-group-ingress --group-id $dbsg --source-group $sgid --protocol tcp --port 5432 || fail
echo "API security group $sgid authorized to connect to database security group $dbsg"

# Upload the application version
aws s3 mb s3://$identifier
aws s3 cp app-version.json s3://$identifier/
aws elasticbeanstalk create-application-version \
    --application-name "$identifier" \
    --version-label invoicer-api \
    --source-bundle "S3Bucket=$identifier,S3Key=app-version.json" > tmp/$identifier/app-version-s3.json

# Wait for the environment to be ready (green)
echo -n "waiting for environment"
while true; do
    aws elasticbeanstalk describe-environments --environment-id $apieid > tmp/$identifier/$apieid.json
    health="$(jq -r '.Environments[0].Health' tmp/$identifier/$apieid.json)"
    if [ "$health" == "Green" ]; then break; fi
    echo -n '.'
    sleep 10
done
echo

# Deploy the docker container to the instances
aws elasticbeanstalk update-environment \
    --application-name $identifier \
    --environment-id $apieid \
    --version-label invoicer-api > tmp/$identifier/$apieid.json

url="$(jq -r '.CNAME' tmp/$identifier/$apieid.json)"
echo "Environment is being deployed. Public endpoint is http://$url"
