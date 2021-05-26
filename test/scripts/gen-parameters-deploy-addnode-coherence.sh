#!/bin/bash
#Generate parameters with value for deploying addnode template

parametersPath=$1
adminPasswordOrKey=$2
adminVMName=$3
adminUsername=$4
numberOfExistingCacheNodes=$5
skuUrnVersion=$6
storageAccountName=${7}
wlsDomainName=${8}
location=${9}
wlsusername=${10}
wlspassword=${11}
gitUserName=${12}
testbranchName=${13}
managedServerPrefix=${14}

cat <<EOF > ${parametersPath}
{
     "adminPasswordOrKey":{
        "value": "${adminPasswordOrKey}"
      },
      "adminVMName": {
        "value": "${adminVMName}"
      },
      "adminUsername": {
        "value": "${adminUsername}"
      },
      "numberOfExistingCacheNodes": {
        "value": ${numberOfExistingCacheNodes}
      },
      "numberOfNewCacheNodes": {
        "value": 1
      },
      "location": {
        "value": "${location}"
      },
      "skuUrnVersion": {
        "value": "${skuUrnVersion}"
      },
      "storageAccountName": {
        "value": "${storageAccountName}"
      },
      "vmSizeSelectForCoherence": {
            "value": "Standard_D2as_v4"
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
        "value": "https://raw.githubusercontent.com/${gitUserName}/arm-oraclelinux-wls-dynamic-cluster/${testbranchName}/addnode-coherence/src/main/"
      },
      "managedServerPrefix": {
        "value": "${managedServerPrefix}"
      }
    }
EOF
