#!/bin/bash

parametersPath=$1
githubUserName=$2
testbranchName=$3
keyVaultName=$4
keyVaultResourceGroup=$5
keyVaultSSLCertDataSecretName=$6
keyVaultSSLCertPasswordSecretName=$7

cat <<EOF > ${parametersPath}
{
    "\$schema": "https://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
    "contentVersion": "1.0.0.0",
    "parameters": {
        "_artifactsLocation": {
            "value": "https://raw.githubusercontent.com/${githubUserName}/arm-oraclelinux-wls-dynamic-cluster/${testbranchName}/arm-oraclelinux-wls-dynamic-cluster/src/main/arm/"
        },
        "_artifactsLocationSasToken": {
            "value": ""
        },
        "adminPasswordOrKey": {
            "value": "GEN-UNIQUE"
        },
        "adminUsername": {
            "value": "GEN-UNIQUE"
        },
        "enableAAD": {
            "value": false
        },
        "enableAppGateway": {
            "value": true
        },
        "enableDB": {
            "value": false
        },
        "keyVaultName": {
            "value": "${keyVaultName}"
        },
        "keyVaultResourceGroup": {
            "value": "${keyVaultResourceGroup}"
        },
        "keyVaultSSLCertDataSecretName": {
            "value": "${keyVaultSSLCertDataSecretName}"
        },
        "keyVaultSSLCertPasswordSecretName": {
            "value": "${keyVaultSSLCertPasswordSecretName}"
        },
        "dynamicClusterSize": {
            "value": 4
        },
        "maxDynamicClusterSize": {
            "value": 2
        },
        "wlsPassword": {
            "value": "GEN-UNIQUE"
        },
        "wlsUserName": {
            "value": "GEN-UNIQUE"
        }
    }
}
EOF
