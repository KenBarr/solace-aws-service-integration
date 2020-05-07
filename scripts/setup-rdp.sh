#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize our own variables:
admin_username=""
admin_password=""
apiGwId=""
apiPath=""
apiStage=""
awsRegion=""
vmr="localhost:8080"
vpn="default"
DEBUG="-vvvv"

verbose=0

while getopts "a:h:u:p:r:s:v:n:" opt; do
    case "$opt" in
    a)  apiGwId=$OPTARG
        ;;
    h)  apiPath=$OPTARG
        ;;
    u)  admin_username=$OPTARG
        ;;
    p)  admin_password=$OPTARG
        ;;
    r)  awsRegion=$OPTARG
        ;;
    s)  apiStage=$OPTARG
        ;;
    v)  vmr=$OPTARG
        ;;
    n)  vpn=$OPTARG
        ;;   
    esac
done

shift $((OPTIND-1))
[ "$1" = "--" ] && shift

verbose=1
echo "apiGwId=${apiGwId} ,apiStage=${apiStage} ,apiPath=${apiPath} \
      ,admin_username=$admin_username ,awsRegion=${awsRegion} ,Leftovers: $@"


echo "`date` INFO: Setting up aws trusted root"
wget -q -O /var/lib/docker/volumes/jail/_data/certs/AmazonRootCA1.pem -nv https://www.amazontrust.com/repository/AmazonRootCA1.pem

online_results=`./semp_query.sh -n ${admin_username} -p ${admin_password} -u http://${vmr}/SEMP \
    -q "<rpc semp-version='soltr/8_9VMR'><authentication><create><certificate-authority><ca-name>aws</ca-name></certificate-authority></create></authentication></rpc>" \
    -v "/rpc-reply/execute-result/@code"`
ca_created=`echo ${online_results} | jq '.valueSearchResult' -`
echo "`date` INFO: certificate-authority created status: ${ca_created}"

online_results=`./semp_query.sh -n ${admin_username} -p ${admin_password} -u http://${vmr}/SEMP \
    -q "<rpc semp-version='soltr/8_9VMR'><authentication><certificate-authority><ca-name>aws</ca-name><certificate><ca-certificate>AmazonRootCA1.pem</ca-certificate></certificate></certificate-authority></authentication></rpc>" \
    -v "/rpc-reply/execute-result/@code"`
ca_loaded=`echo ${online_results} | jq '.valueSearchResult' -`
echo "`date` INFO: certificate-authority file loaded status: ${ca_loaded}"

echo "`date` INFO: Setting up Solace Queue"
curl --user ${admin_username}:${admin_password} \
     --request POST \
     --header "content-type:application/json" \
     --data "{\"queueName\":\"aws_service_${apiPath}_queue\",\"egressEnabled\":true,\"ingressEnabled\":true,\"permission\":\"delete\"}" \
    "http://${vmr}/SEMP/v2/config/msgVpns/${vpn}/queues"

curl --user ${admin_username}:${admin_password} \
     --request POST \
     --header "content-type:application/json" \
     --data "{\"msgVpnName\":\"${vpn}\",\"queueName\":\"aws_service_${apiPath}_queue\",\"subscriptionTopic\":\"solace-aws-service-integration/${apiPath}\"}" \
     "http://${vmr}/SEMP/v2/config/msgVpns/${vpn}/queues/aws_service_${apiPath}_queue/subscriptions" 

echo "`date` INFO: Setting up Rest Delivery Endpoint"
curl --user ${admin_username}:${admin_password} \
     --request PATCH \
     --header "content-type:application/json" \
     --data "{\"msgVpnName\":\"${vpn}\",\"restTlsServerCertEnforceTrustedCommonNameEnabled\":false}" \
     "http://${vmr}/SEMP/v2/config/msgVpns/${vpn}"

curl --user ${admin_username}:${admin_password} \
     --request POST \
     --header "content-type:application/json" \
     --data "{\"enabled\":true,\"msgVpnName\":\"${vpn}\",\"restDeliveryPointName\":\"aws_service_rpd\"}" \
     "http://${vmr}/SEMP/v2/config/msgVpns/${vpn}/restDeliveryPoints"

curl --user ${admin_username}:${admin_password} \
     --request POST \
     --header "content-type:application/json" \
     --data "{\"msgVpnName\":\"${vpn}\",\"postRequestTarget\":\"/${apiStage}/${apiPath}\",\"queueBindingName\":\"aws_service_${apiPath}_queue\",\"restDeliveryPointName\":\"aws_service_rpd\"}" \
     "http://${vmr}/SEMP/v2/config/msgVpns/${vpn}/restDeliveryPoints/aws_service_rpd/queueBindings"

curl --user ${admin_username}:${admin_password} \
     --request POST \
     --header "content-type:application/json" \
     --data "{\"enabled\":true,\"msgVpnName\":\"${vpn}\",\"remoteHost\":\"${apiGwId}.execute-api.${awsRegion}.amazonaws.com\",\"remotePort\":443,\"restConsumerName\":\"aws_service_rc\",\"tlsEnabled\":true}" \
     "http://${vmr}/SEMP/v2/config/msgVpns/${vpn}/restDeliveryPoints/aws_service_rpd/restConsumers"
