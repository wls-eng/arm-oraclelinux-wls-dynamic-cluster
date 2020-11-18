#!/bin/bash
#Generate parameters with value for deploying coherence template independently

parametersPath=$1
adminVMName=$2
adminPasswordOrKey=$3
skuUrnVersion=$4
location=$5
storageAccountName=$6
wlsDomainName=$7
wlsusername=$8
wlspassword=$9
gitUserName=${10}
testbranchName=${11}
managedServerPrefix=${12}

cat <<EOF > ${parametersPath}
{
     "adminVMName":{
        "value": "${adminVMName}"
      },
      "adminPasswordOrKey": {
        "value": "${adminPasswordOrKey}"
      },
      "enableCoherenceWebLocalStorage": {
        "value": true
      },
      "numberOfCoherenceCacheInstances": {
        "value": 1
      },
      "skuUrnVersion": {
        "value": "${skuUrnVersion}"
      },
      "location": {
        "value": "${location}"
      },
      "storageAccountName": {
        "value": "${storageAccountName}"
      },
      "wlsDomainName": {
        "value": "${wlsDomainName}"
      },
      "wlsPassword": {
        "value": "${wlsPassword}"
      },
      "wlsUserName": {
        "value": "${wlsUserName}"
      },
      "_artifactsLocation":{
        "value": "https://raw.githubusercontent.com/${gitUserName}/arm-oraclelinux-wls-dynamic-cluster/${testbranchName}/arm-oraclelinux-wls-dynamic-cluster/src/main/arm/"
      },
      "managedServerPrefix": {
        "value": "${managedServerPrefix}"
      }
    }
EOF
