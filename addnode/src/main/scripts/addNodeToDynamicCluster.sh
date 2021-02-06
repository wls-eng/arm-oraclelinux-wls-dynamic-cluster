#!/bin/bash

#Function to output message to StdErr
function echo_stderr ()
{
    echo "$@" >&2
}

#Function to display usage message
function usage()
{
  echo_stderr "./addnode.sh <wlsDomainName> <wlsUserName> <wlsPassword> <managedServerPrefix> <serverIndex> <wlsAdminURL> <oracleHome> <wlsDomainPath> <dynamicClusterSize> <vmNamePrefix> <storageAccountName> <storageAccountKey> <mountpointPath> <wlsADSSLCer> <wlsLDAPPublicIP> <adServerHost> <enableELK> <elasticURI> <elasticUserName> <elasticPassword> <logsToIntegrate> <logIndex> <maxDynamicClusterSize>  <isCustomSSLenabled> <customIdentityKeyStoreBase64String> <customIdentityKeyStorePassPhrase> <customIdentityKeyStoreType> <customTrustKeyStoreBase64String> <customTrustKeyStorePassPhrase> <customTrustKeyStoreType> <privateKeyAlias> <privateKeyPassPhrase>"
}

function installUtilities()
{
    echo "Installing zip unzip wget vnc-server rng-tools cifs-utils"
    sudo yum install -y zip unzip wget vnc-server rng-tools cifs-utils

    #Setting up rngd utils
    attempt=1
    while [[ $attempt -lt 4 ]]
    do
       echo "Starting rngd service attempt $attempt"
       sudo systemctl start rngd
       attempt=`expr $attempt + 1`
       sudo systemctl status rngd | grep running
       if [[ $? == 0 ]]; 
       then
          echo "rngd utility service started successfully"
          break
       fi
       sleep 1m
    done  
}

function validateInput()
{
    if [ -z "$wlsDomainName" ];
    then
        echo_stderr "wlsDomainName is required. "
    fi

    if [[ -z "$wlsUserName" || -z "$wlsPassword" ]]
    then
        echo_stderr "wlsUserName or wlsPassword is required. "
        exit 1
    fi	

    if [ -z "$managedServerPrefix" ];
    then
        echo_stderr "managedServerPrefix is required. "
    fi

    if [ -z "$serverIndex" ];
    then
        echo_stderr "serverIndex is required. "
    fi

    if [ -z "$wlsAdminURL" ];
    then
        echo_stderr "wlsAdminURL is required. "
    fi

    if [ -z "$oracleHome" ]; then
        echo_stderr "oracleHome is required. "
    fi

    if [ -z "$wlsDomainPath" ]; then
        echo_stderr "wlsDomainPath is required. "
    fi

    if [ -z "$dynamicClusterSize" ];
    then
        echo_stderr "dynamicClusterSize is required. "
    fi

    if [ -z "$vmNamePrefix" ];
    then
        echo_stderr "vmNamePrefix is required. "
    fi

    if [ -z "$storageAccountName" ]; then
        echo_stderr "storageAccountName is required. "
    fi

    if [ -z "$storageAccountKey" ]; then
        echo_stderr "storageAccountKey is required. "
    fi

    if [ -z "$mountpointPath" ]; then
        echo_stderr "mountpointPath is required. "
    fi

    if [[ -z "$wlsADSSLCer" || -z "$wlsLDAPPublicIP" || -z "$adServerHost" ]]; then
        echo_stderr "wlsADSSLCer, wlsLDAPPublicIP and adServerHost are required. "
        exit 1
    fi

    if [[ "$wlsADSSLCer" != "null" && "$wlsLDAPPublicIP" != "null" && "$adServerHost" != "null" ]]; then
        enableAAD="true"
    fi

    if [ -z "$enableELK" ]; then
        echo_stderr "enableELK is required. "
    fi

    if [ -z "$elasticURI" ]; then
        echo_stderr "elasticURI is required. "
    fi

    if [ -z "$elasticUserName" ]; then
        echo_stderr "elasticUserName is required. "
    fi

    if [ -z "$elasticPassword" ]; then
        echo_stderr "elasticPassword is required. "
    fi

    if [ -z "$logsToIntegrate" ]; then
        echo_stderr "logsToIntegrate is required. "
    fi

    if [ -z "$logIndex" ]; then
        echo_stderr "logIndex is required. "
    fi

    if [ -z "$maxDynamicClusterSize" ]; then
        echo_stderr "maxDynamicClusterSize is required. "
    fi

    if [ ! -z "$isCustomSSLEnabled" == "true" ];
    then
        if [[ -z "$customIdentityKeyStoreBase64String" || -z "$customIdentityKeyStorePassPhrase"  || -z "$customIdentityKeyStoreType" ||
              -z "$customTrustKeyStoreBase64String" || -z "$customTrustKeyStorePassPhrase"  || -z "$customTrustKeyStoreType" ||
              -z "$privateKeyAlias" || -z "$privateKeyPassPhrase" ]]
        then
            echo_stderr "customIdentityKeyStoreBase64String, customIdentityKeyStorePassPhrase, customIdentityKeyStoreType, customTrustKeyStoreBase64String, customTrustKeyStorePassPhrase, customTrustKeyStoreType, privateKeyAlias and privateKeyPassPhrase are required. "
            exit 1
        fi
    fi
}

#Function to cleanup all temporary files
function cleanup()
{
    echo "Cleaning up temporary files..."

    rm -rf $wlsDomainPath/managed-domain.yaml
    rm -rf $wlsDomainPath/weblogic-deploy.zip
    rm -rf $wlsDomainPath/weblogic-deploy
    rm -rf $wlsDomainPath/deploy-app.yaml
    rm -rf $wlsDomainPath/shoppingcart.zip
    rm -rf $wlsDomainPath/*.py
    echo "Cleanup completed."
}

#Creates weblogic deployment model for managed server domain
function create_managed_server_domain()
{
    echo "Creating managed server domain"
    cat <<EOF >$wlsDomainPath/managed-domain.yaml
domainInfo:
   AdminUserName: "$wlsUserName"
   AdminPassword: "$wlsPassword"
   ServerStartMode: prod
topology:
   Name: "$wlsDomainName"
   Machine:
     '$machineName':
         NodeManager:
            ListenAddress: "$nmHost"
            ListenPort: $nmPort
            NMType : ssl  
   Cluster:
        '$wlsClusterName':
            MigrationBasis: 'consensus'
            DynamicServers:
                ServerTemplate: '${dynamicServerTemplate}'
                DynamicClusterSize: ${dynamicClusterSize}
                MaxDynamicClusterSize: ${maxDynamicClusterSize}
                CalculatedListenPorts: true
                CalculatedMachineNames: true
                ServerNamePrefix: "${managedServerPrefix}"
                MachineNameMatchExpression: "machine-${vmNamePrefix}*"
   ServerTemplate:
        '${dynamicServerTemplate}' :
            ListenPort: ${wlsManagedPort}
            Cluster: '${wlsClusterName}'
            SSL:
                HostnameVerificationIgnored: true
                HostnameVerifier: 'None'
EOF

        if [ "${isCustomSSLEnabled}" == "true" ];
        then
cat <<EOF>>$DOMAIN_PATH/managed-domain.yaml
                ServerPrivateKeyAlias: "$serverPrivateKeyAlias"
                ServerPrivateKeyPassPhraseEncrypted: "$serverPrivateKeyPassPhrase"
EOF
        fi

        if [ "${isCustomSSLEnabled}" == "true" ];
        then
cat <<EOF>>$DOMAIN_PATH/managed-domain.yaml
            KeyStores: 'CustomIdentityAndCustomTrust'
            CustomIdentityKeyStoreFileName: "$customIdentityKeyStoreFileName"
            CustomIdentityKeyStoreType: "$customIdentityKeyStoreType"
            CustomIdentityKeyStorePassPhraseEncrypted: "$customIdentityKeyStorePassPhrase"
            CustomTrustKeyStoreFileName: "$customTrustKeyStoreFileName"
            CustomTrustKeyStoreType: "$customTrustKeyStoreType"
            CustomTrustKeyStorePassPhraseEncrypted: "$customTrustKeyStorePassPhrase"
EOF
        fi

cat <<EOF>>$DOMAIN_PATH/managed-domain.yaml
   SecurityConfiguration:
        NodeManagerUsername: "$wlsUserName"
        NodeManagerPasswordEncrypted: "$wlsPassword"
EOF
}

#This function create py Script to create Machine on the Domain
function createMachinePyScript()
{
    echo "Creating machine name model: $machineName"
    cat <<EOF >$wlsDomainPath/add-machine.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
shutdown('$wlsClusterName', 'Cluster')
edit("$machineName")
startEdit()
cd('/')
cmo.createMachine('$machineName')
cd('/Machines/$machineName/NodeManager/$machineName')
cmo.setListenPort(int($nmPort))
cmo.setListenAddress('$nmHost')
cmo.setNMType('ssl')
save()
resolve()
activate()
destroyEditSession("$machineName")
disconnect()
EOF
}


#This function creates py Script to enroll Node Manager to the Domain
function createEnrollServerPyScript()
{
    echo "Creating managed server model"
    cat <<EOF >$wlsDomainPath/enroll-server.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
nmEnroll('$wlsDomainPath/$wlsDomainName','$wlsDomainPath/$wlsDomainName/nodemanager')
disconnect()
EOF
}

#This function to wait for admin server 
function wait_for_admin()
{
 #wait for admin to start
count=1
export CHECK_URL="http://$wlsAdminURL/weblogic/ready"
status=`curl --insecure -ILs $CHECK_URL | tac | grep -m1 HTTP/1.1 | awk {'print $2'}`
while [[ "$status" != "200" ]]
do
  echo "Waiting for admin server to start"
  count=$((count+1))
  if [ $count -le 30 ];
  then
      sleep 1m
  else
     echo "Error : Maximum attempts exceeded while starting admin server"
     exit 1
  fi
  status=`curl --insecure -ILs $CHECK_URL | tac | grep -m1 HTTP/1.1 | awk {'print $2'}`
  if [ "$status" == "200" ];
  then
     echo "Admin Server started succesfully..."
     break
  fi
done  
}

#This function to start managed server
function start_cluster()
{
    echo "Starting Cluster $wlsClusterName"
    cat <<EOF >$wlsDomainPath/start-server.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
try:
   start('$wlsClusterName', 'Cluster')
except:
   print "Failed starting Cluster $wlsClusterName"
   dumpStack()
disconnect()
EOF
sudo chown -R $username:$groupname $wlsDomainPath
runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; java $WLST_ARGS weblogic.WLST $wlsDomainPath/start-server.py"
if [[ $? != 0 ]]; then
  echo "Error : Failed in starting cluster"
  exit 1
fi
}

#Function to start nodemanager
function start_nm()
{
   runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; \"$wlsDomainPath/$wlsDomainName/bin/startNodeManager.sh\" &"
   sleep 1m
}

function create_managedSetup(){

    echo "Creating Managed Server Setup"
    echo "Creating domain path /u01/domains"
    echo "Downloading weblogic-deploy-tool"
    cd $wlsDomainPath
    wget -q $WEBLOGIC_DEPLOY_TOOL  
    if [[ $? != 0 ]]; then
       echo "Error : Downloading weblogic-deploy-tool failed"
       exit 1
    fi
    sudo unzip -o weblogic-deploy.zip -d $wlsDomainPath
    echo "Creating managed server model files"
    
    create_managed_server_domain
    
    createMachinePyScript
    
    createEnrollServerPyScript
    
    echo "Completed managed server model files"
    sudo chown -R $username:$groupname $wlsDomainPath
    
    runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; $wlsDomainPath/weblogic-deploy/bin/createDomain.sh -oracle_home ${oracleHome} -domain_parent $wlsDomainPath  -domain_type WLS -model_file $wlsDomainPath/managed-domain.yaml" 
    
    if [[ $? != 0 ]]; then
       echo "Error : Managed setup failed"
       exit 1
    fi
    
    wait_for_admin

    # For issue https://github.com/wls-eng/arm-oraclelinux-wls/issues/89
    getSerializedSystemIniFileFromShare
    
    echo "Adding Machine $machineName"
    runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; java $WLST_ARGS weblogic.WLST $wlsDomainPath/add-machine.py"
    if [[ $? != 0 ]]; then
         echo "Error : Adding machine $machineName failed"
         exit 1
    fi
    
    echo "Enrolling Domain for Machine $machineName"
    runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; java $WLST_ARGS weblogic.WLST $wlsDomainPath/enroll-server.py"
    if [[ $? != 0 ]]; then
         echo "Error : Enrolling machine $machineName failed"
         exit 1
    fi
}

# Create systemctl service for nodemanager
function create_nodemanager_service()
{
 echo "Creating services for Nodemanager"
 echo "Setting CrashRecoveryEnabled true at $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties"
 sed -i.bak -e 's/CrashRecoveryEnabled=false/CrashRecoveryEnabled=true/g'  $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties
 if [ $? != 0 ];
 then
   echo "Warning : Failed in setting option CrashRecoveryEnabled=true. Continuing without the option."
   mv $wlsDomainPath/nodemanager/nodemanager.properties.bak $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties
 fi

 if [ "${isCustomSSLEnabled}" == "true" ];
 then
    echo "KeyStores=CustomIdentityAndCustomTrust" >> $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties
    echo "CustomIdentityKeyStoreFileName=${customSSLIdentityKeyStoreFile}" >> $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties
    echo "CustomIdentityAlias=${privateKeyAlias}" >> $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties
    echo "CustomIdentityPrivateKeyPassPhrase=${customIdentityKeyStorePassPhrase}" >> $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties
    echo "CustomTrustKeyStoreFileName=${customSSLTrustKeyStoreFile}" >> $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties
 fi

 sudo chown -R $username:$groupname $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties*
 echo "Creating NodeManager service"
 cat <<EOF >/etc/systemd/system/wls_nodemanager.service
 [Unit]
Description=WebLogic nodemanager service
 
[Service]
Type=simple
# Note that the following three parameters should be changed to the correct paths
# on your own system
WorkingDirectory="$wlsDomainPath/$wlsDomainName"
ExecStart="$wlsDomainPath/$wlsDomainName/bin/startNodeManager.sh"
ExecStop="$wlsDomainPath/$wlsDomainName/bin/stopNodeManager.sh"
User=oracle
Group=oracle
KillMode=process
LimitNOFILE=65535
 
[Install]
WantedBy=multi-user.target
EOF
echo "Created service for Nodemanager"
}

function enabledAndStartNodeManagerService()
{
  sudo systemctl enable wls_nodemanager
  sudo systemctl daemon-reload
  echo "Starting nodemanager service"
  sudo systemctl start wls_nodemanager
}

function updateNetworkRules()
{
    # for Oracle Linux 7.3, 7.4, iptable is not running.
    if [ -z `command -v firewall-cmd` ]; then
        return 0
    fi
    
    # for Oracle Linux 7.6, open weblogic ports
    tag=$1
    if [ ${tag} == 'admin' ]; then
        echo "update network rules for admin server"
        sudo firewall-cmd --zone=public --add-port=$wlsAdminPort/tcp
        sudo firewall-cmd --zone=public --add-port=$wlsSSLAdminPort/tcp
        sudo firewall-cmd --zone=public --add-port=$wlsManagedPort/tcp
        sudo firewall-cmd --zone=public --add-port=$nmPort/tcp
    else
        echo "update network rules for managed server"
        sudo firewall-cmd --zone=public --add-port=$wlsManagedPort/tcp
        sudo firewall-cmd --zone=public --add-port=$nmPort/tcp
    fi

    sudo firewall-cmd --runtime-to-permanent
    sudo systemctl restart firewalld
}

# Mount the Azure file share on all VMs created
function mountFileShare()
{
  echo "Creating mount point"
  echo "Mount point: $mountpointPath"
  sudo mkdir -p $mountpointPath
  if [ ! -d "/etc/smbcredentials" ]; then
    sudo mkdir /etc/smbcredentials
  fi
  if [ ! -f "/etc/smbcredentials/${storageAccountName}.cred" ]; then
    echo "Crearing smbcredentials"
    echo "username=$storageAccountName >> /etc/smbcredentials/${storageAccountName}.cred"
    echo "password=$storageAccountKey >> /etc/smbcredentials/${storageAccountName}.cred"
    sudo bash -c "echo "username=$storageAccountName" >> /etc/smbcredentials/${storageAccountName}.cred"
    sudo bash -c "echo "password=$storageAccountKey" >> /etc/smbcredentials/${storageAccountName}.cred"
  fi
  echo "chmod 600 /etc/smbcredentials/${storageAccountName}.cred"
  sudo chmod 600 /etc/smbcredentials/${storageAccountName}.cred
  echo "//${storageAccountName}.file.core.windows.net/wlsshare $mountpointPath cifs nofail,vers=2.1,credentials=/etc/smbcredentials/${storageAccountName}.cred ,dir_mode=0777,file_mode=0777,serverino"
  sudo bash -c "echo \"//${storageAccountName}.file.core.windows.net/wlsshare $mountpointPath cifs nofail,vers=2.1,credentials=/etc/smbcredentials/${storageAccountName}.cred ,dir_mode=0777,file_mode=0777,serverino\" >> /etc/fstab"
  echo "mount -t cifs //${storageAccountName}.file.core.windows.net/wlsshare $mountpointPath -o vers=2.1,credentials=/etc/smbcredentials/${storageAccountName}.cred,dir_mode=0777,file_mode=0777,serverino"
  sudo mount -t cifs //${storageAccountName}.file.core.windows.net/wlsshare $mountpointPath -o vers=2.1,credentials=/etc/smbcredentials/${storageAccountName}.cred,dir_mode=0777,file_mode=0777,serverino
  if [[ $? != 0 ]];
  then
         echo "Failed to mount //${storageAccountName}.file.core.windows.net/wlsshare $mountpointPath"
	 exit 1
  fi
}

# Get SerializedSystemIni.dat file from share point to managed server vm
function getSerializedSystemIniFileFromShare()
{
  runuser -l oracle -c "mv ${wlsDomainPath}/${wlsDomainName}/security/SerializedSystemIni.dat ${wlsDomainPath}/${wlsDomainName}/security/SerializedSystemIni.dat.backup"
  runuser -l oracle -c "cp ${mountpointPath}/SerializedSystemIni.dat ${wlsDomainPath}/${wlsDomainName}/security/."
  ls -lt ${wlsDomainPath}/${wlsDomainName}/security/SerializedSystemIni.dat
  if [[ $? != 0 ]]; 
  then
      echo "Failed to get ${mountpointPath}/SerializedSystemIni.dat"
      exit 1
  fi
  runuser -l oracle -c "chmod 640 ${wlsDomainPath}/${wlsDomainName}/security/SerializedSystemIni.dat"
}

function mapLDAPHostWithPublicIP()
{
    echo "map LDAP host with pubilc IP"
    
    # remove existing ip address for the same host
    sudo sed -i '/${adServerHost}/d' /etc/hosts
    sudo echo "${wlsLDAPPublicIP}  ${adServerHost}" >> /etc/hosts
}

function parseLDAPCertificate()
{
    echo "create key store"
    cer_begin=0
    cer_size=${#wlsADSSLCer}
    cer_line_len=64
    mkdir ${SCRIPT_PWD}/security
    touch ${SCRIPT_PWD}/security/AzureADLDAPCerBase64String.txt
    while [ ${cer_begin} -lt ${cer_size} ]
    do
        cer_sub=${wlsADSSLCer:$cer_begin:$cer_line_len}
        echo ${cer_sub} >> ${SCRIPT_PWD}/security/AzureADLDAPCerBase64String.txt
        cer_begin=$((cer_begin+$cer_line_len))
    done

    openssl base64 -d -in ${SCRIPT_PWD}/security/AzureADLDAPCerBase64String.txt -out ${SCRIPT_PWD}/security/AzureADTrust.cer
    export addsCertificate=${SCRIPT_PWD}/security/AzureADTrust.cer
}

function importAADCertificate()
{
    # import the key to java security 
    . $oracleHome/oracle_common/common/bin/setWlstEnv.sh
    # For AAD failure: exception happens when importing certificate to JDK 11.0.7
    # ISSUE: https://github.com/wls-eng/arm-oraclelinux-wls/issues/109
    # JRE was removed since JDK 11.
    java_version=$(java -version 2>&1 | sed -n ';s/.* version "\(.*\)\.\(.*\)\..*"/\1\2/p;')
    if [ ${java_version:0:3} -ge 110 ]; 
    then 
        java_cacerts_path=${JAVA_HOME}/lib/security/cacerts
    else
        java_cacerts_path=${JAVA_HOME}/jre/lib/security/cacerts
    fi

    # remove existing certificate.
    queryAADTrust=$(${JAVA_HOME}/bin/keytool -list -keystore ${java_cacerts_path} -storepass changeit | grep "aadtrust")
    if [ -n "${queryAADTrust}" ];
    then
        sudo ${JAVA_HOME}/bin/keytool -delete -alias aadtrust -keystore ${java_cacerts_path} -storepass changeit  
    fi

    sudo ${JAVA_HOME}/bin/keytool -noprompt -import -alias aadtrust -file ${addsCertificate} -keystore ${java_cacerts_path} -storepass changeit
}

function importAADCertificateIntoWLSCustomTrustKeyStore()
{
    if [ "${isCustomSSLEnabled,,}" == "true" ];
    then
        # set java home
        . $oracleHome/oracle_common/common/bin/setWlstEnv.sh

        # For SSL enabled causes AAD failure #225
        # ISSUE: https://github.com/wls-eng/arm-oraclelinux-wls/issues/225

        echo "Importing AAD Certificate into WLS Custom Trust Key Store: "

        sudo ${JAVA_HOME}/bin/keytool -noprompt -import -trustcacerts -keystore {KEYSTORE_PATH}/trust.keystore -storepass ${customTrustKeyStorePassPhrase} -alias aadtrust -file ${addsCertificate} -storetype ${customTrustKeyStoreType}
    else
        echo "customSSL not enabled. Not required to configure AAD for WebLogic Custom SSL"
    fi
}

function parseAndSaveCustomSSLKeyStoreData()
{
    echo "create key stores for custom ssl settings"

    mkdir -p ${KEYSTORE_PATH}
    touch ${KEYSTORE_PATH}/identityKeyStoreCerBase64String.txt

    echo "$customIdentityKeyStoreBase64String" > ${KEYSTORE_PATH}/identityKeyStoreCerBase64String.txt
    cat ${KEYSTORE_PATH}/identityKeyStoreCerBase64String.txt | base64 -d > ${KEYSTORE_PATH}/identity.keystore
    export customSSLIdentityKeyStoreFile=${KEYSTORE_PATH}/identity.keystore

    rm -rf ${KEYSTORE_PATH}/identityKeyStoreCerBase64String.txt

    mkdir -p ${KEYSTORE_PATH}
    touch ${KEYSTORE_PATH}/trustKeyStoreCerBase64String.txt

    echo "$customTrustKeyStoreBase64String" > ${KEYSTORE_PATH}/trustKeyStoreCerBase64String.txt
    cat ${KEYSTORE_PATH}/trustKeyStoreCerBase64String.txt | base64 -d > ${KEYSTORE_PATH}/trust.keystore
    export customSSLTrustKeyStoreFile=${KEYSTORE_PATH}/trust.keystore

    rm -rf ${KEYSTORE_PATH}/trustKeyStoreCerBase64String.txt
}

#main script starts here

export SCRIPT_PWD=`pwd`

# store arguments in a special array 
args=("$@") 
# get number of elements 
ELEMENTS=${#args[@]} 

# echo each element in array  
# for loop 
for (( i=0;i<$ELEMENTS;i++)); do 
    echo "ARG[${args[${i}]}]"
done

if [ $# -lt 24 ]
then
    usage
    exit 1
fi

export wlsDomainName=$1
export wlsUserName=$2
export wlsPassword=$3
export managedServerPrefix=$4
export serverIndex=$5
export wlsAdminURL=$6
export oracleHome=${7}
export wlsDomainPath=${8}
export dynamicClusterSize=${9}
export vmNamePrefix=${10}
export storageAccountName=${11}
export storageAccountKey=${12}
export mountpointPath=${13}
export wlsADSSLCer="${14}"
export wlsLDAPPublicIP="${15}"
export adServerHost="${16}"
export enableELK=${17}
export elasticURI=${18}
export elasticUserName=${19}
export elasticPassword=${20}
export logsToIntegrate=${21}
export logIndex=${22}
export maxDynamicClusterSize=${23}

export isCustomSSLEnabled="${24}"
isCustomSSLEnabled="${isCustomSSLEnabled,,}"

export customIdentityKeyStoreBase64String="${25}"
export customIdentityKeyStorePassPhrase="${26}"
export customIdentityKeyStoreType="${27}"
export customTrustKeyStoreBase64String="${28}"
export customTrustKeyStorePassPhrase="${29}"
export customTrustKeyStoreType="${30}"
export privateKeyAlias="${31}"
export privateKeyPassPhrase="${32}"

export enableAAD="false"

validateInput

export nmHost=`hostname`
export nmPort=5556
export wlsAdminPort=7001
export wlsSSLAdminPort=7002
export wlsManagedPort=8001
export wlsClusterName="cluster1"
export dynamicServerTemplate="myServerTemplate"
export machineNamePrefix="machine"
export machineName="$machineNamePrefix-$nmHost"
export WEBLOGIC_DEPLOY_TOOL=https://github.com/oracle/weblogic-deploy-tooling/releases/download/weblogic-deploy-tooling-1.8.1/weblogic-deploy.zip
export username="oracle"
export groupname="oracle"
export KEYSTORE_PATH="$wlsDomainPath/$wlsDomainName/keystores"

cleanup
installUtilities
mountFileShare
updateNetworkRules "managed"

if [ "$isCustomSSLEnabled" == "true" ];then
    parseAndSaveCustomSSLKeyStoreData
fi


if [ "$enableAAD" == "true" ];then
    mapLDAPHostWithPublicIP
    parseLDAPCertificate
    importAADCertificate
    importAADCertificateIntoWLSCustomTrustKeyStore
fi

create_managedSetup
create_nodemanager_service
enabledAndStartNodeManagerService
start_cluster

echo "enable ELK? ${enableELK}"
if [[ "${enableELK,,}" == "true" ]];then
    echo "Set up ELK..."
    ${SCRIPT_PWD}/elkIntegrationForDynamicCluster.sh \
        ${oracleHome} \
        ${wlsAdminURL} \
        ${managedServerPrefix} \
        ${wlsUserName} \
        ${wlsPassword} \
        "admin" \
        ${elasticURI} \
        ${elasticUserName} \
        ${elasticPassword} \
        ${wlsDomainName} \
        ${wlsDomainPath}/${wlsDomainName} \
        ${logsToIntegrate} \
        ${serverIndex} \
        ${logIndex} \
        ${maxDynamicClusterSize}
fi

cleanup