#!/bin/bash

#Function to output message to StdErr
function echo_stderr() {
    echo "$@" >&2
}

#Function to display usage message
function usage() {
    echo_stderr "./setupCoherence.sh <wlsDomainName> <wlsUserName> <wlsPassword> <wlsServerName> <adminVMName> <oracleHome> <wlsDomainPath> <storageAccountName> <storageAccountKey> <mountpointPath> <enableWebLocalStorage> <enableELK> <elasticURI> <elasticUserName> <elasticPassword> <logsToIntegrate> <logIndex> <managedServerPrefix> <serverIndex>"
}

function installUtilities() {
    echo "Installing zip unzip wget vnc-server rng-tools cifs-utils"
    sudo yum install -y zip unzip wget vnc-server rng-tools cifs-utils

    #Setting up rngd utils
    attempt=1
    while [[ $attempt -lt 4 ]]; do
        echo "Starting rngd service attempt $attempt"
        sudo systemctl start rngd
        attempt=$(expr $attempt + 1)
        sudo systemctl status rngd | grep running
        if [[ $? == 0 ]]; then
            echo "rngd utility service started successfully"
            break
        fi
        sleep 1m
    done
}

function validateInput() {
    if [ -z "$wlsDomainName" ]; then
        echo_stderr "wlsDomainName is required. "
    fi

    if [[ -z "$wlsUserName" || -z "$wlsPassword" ]]; then
        echo_stderr "wlsUserName or wlsPassword is required. "
        exit 1
    fi

    if [ -z "$wlsServerName" ]; then
        echo_stderr "wlsServerName is required. "
    fi

    if [ -z "$adminVMName" ]; then
        echo_stderr "adminVMName is required. "
    fi

    if [ -z "$oracleHome" ]; then
        echo_stderr "oracleHome is required. "
    fi

    if [ -z "$wlsDomainPath" ]; then
        echo_stderr "wlsDomainPath is required. "
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

    if [ -z "$enableWebLocalStorage" ]; then
        echo_stderr "enableWebLocalStorage is required. "
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

    if [ -z "$serverIndex" ]; then
        echo_stderr "serverIndex is required. "
    fi

    if [ -z "$managedServerPrefix" ]; then
        echo_stderr "managedServerPrefix is required. "
    fi
}

#run on admin server
#create coherence cluster
#associate cluster1 with the coherence cluster
#create configured cluter storage1 and enable local storage
#associate storage1 with the coherence cluster
function createCoherenceClusterModel() {
    cat <<EOF >$wlsDomainPath/configure-coherence-cluster.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
shutdown('$clientClusterName', 'Cluster')
try:
    edit()
    startEdit()
    cd('/')
    cmo.createCoherenceClusterSystemResource('${coherenceClusterName}')

    cd('/CoherenceClusterSystemResources/${coherenceClusterName}/CoherenceClusterResource/${coherenceClusterName}/CoherenceClusterParams/${coherenceClusterName}')
    cmo.setClusteringMode('unicast')
    cmo.setClusterListenPort(${coherenceListenPort})

    cd('/')
    cmo.createCluster('${storageClusterName}')

    cd('/Clusters/${storageClusterName}')
    cmo.setClusterMessagingMode('unicast')
    cmo.setCoherenceClusterSystemResource(getMBean('/CoherenceClusterSystemResources/${coherenceClusterName}'))

    cd('/Clusters/${clientClusterName}')
    cmo.setCoherenceClusterSystemResource(getMBean('/CoherenceClusterSystemResources/${coherenceClusterName}'))

    cd('/CoherenceClusterSystemResources/${coherenceClusterName}')
    cmo.addTarget(getMBean('/Clusters/${storageClusterName}'))
    cmo.addTarget(getMBean('/Clusters/${clientClusterName}'))

    cd('/Clusters/${storageClusterName}/CoherenceTier/${storageClusterName}')
    cmo.setCoherenceWebLocalStorageEnabled(${enableWebLocalStorage})
    cmo.setLocalStorageEnabled(true)

    cd('/Clusters/${clientClusterName}/CoherenceTier/${clientClusterName}')
    cmo.setLocalStorageEnabled(false)

    cd('/ServerTemplates/${wlsServerTemplate}//ServerStart/${wlsServerTemplate}')
    arguments = cmo.getArguments()
    if(str(arguments) == 'None'):
        arguments = '${wlsCoherenceUnicastPortRange}'
    else:
        arguments = str(arguments) + ' ' + '${wlsCoherenceUnicastPortRange}'
    cmo.setArguments(arguments)

    save()
    activate()
except:
    stopEdit('y')
    sys.exit(1)

try: 
    start('$clientClusterName', 'Cluster')
except:
    dumpStack()

disconnect()
sys.exit(0)
EOF

    runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; java $WLST_ARGS weblogic.WLST $wlsDomainPath/configure-coherence-cluster.py"
    if [[ $? != 0 ]]; then
        echo "Error : Create coherence cluster ${coherenceClusterName} failed"
        exit 1
    fi
}

#Creates weblogic deployment model for cluster domain managed server
function create_managed_model() {
    echo "Creating admin domain model"
    cat <<EOF >$wlsDomainPath/managed-domain.yaml
domainInfo:
   AdminUserName: "$wlsUserName"
   AdminPassword: "$wlsPassword"
   ServerStartMode: prod
topology:
   Name: "$wlsDomainName"
   Machine:
     '$nmHost':
         NodeManager:
             ListenAddress: "$nmHost"
             ListenPort: $nmPort
             NMType : ssl  
   Cluster:
        '$storageClusterName':
            MigrationBasis: 'database'
   Server:
        '$wlsServerName' :
           ListenPort: $storageListenPort
           Notes: "$wlsServerName managed server"
           Cluster: "$storageClusterName"
           Machine: "$nmHost"
   SecurityConfiguration:
       NodeManagerUsername: "$wlsUserName"
       NodeManagerPasswordEncrypted: "$wlsPassword" 
EOF
}

#This function to add machine for a given managed server
function create_machine_model() {
    echo "Creating machine name model for managed server $wlsServerName"
    cat <<EOF >$wlsDomainPath/add-machine.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
edit("$wlsServerName")
startEdit()
cd('/')
cmo.createMachine('$nmHost')
cd('/Machines/$nmHost/NodeManager/$nmHost')
cmo.setListenPort(int($nmPort))
cmo.setListenAddress('$nmHost')
cmo.setNMType('ssl')
save()
resolve()
activate()
destroyEditSession("$wlsServerName")
disconnect()
EOF
}

#This function to add managed serverto admin node
function create_ms_server_model() {
    echo "Creating managed server $wlsServerName model"
    cat <<EOF >$wlsDomainPath/add-server.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
edit("$wlsServerName")
startEdit()
cd('/')
cmo.createServer('$wlsServerName')
cd('/Servers/$wlsServerName')
cmo.setMachine(getMBean('/Machines/$nmHost'))
cmo.setCluster(getMBean('/Clusters/$storageClusterName'))
cmo.setListenAddress('$nmHost')
cmo.setListenPort(int($storageListenPort))
cmo.setListenPortEnabled(true)
cd('/Servers/$wlsServerName/SSL/$wlsServerName')
cmo.setEnabled(false)
cd('/Servers/$wlsServerName//ServerStart/$wlsServerName')
arguments = '-Dweblogic.Name=$wlsServerName  -Dweblogic.management.server=http://$wlsAdminURL ${wlsCoherenceUnicastPortRange}'
cmo.setArguments(arguments)
save()
resolve()
activate()
destroyEditSession("$wlsServerName")
nmEnroll('$wlsDomainPath/$wlsDomainName','$wlsDomainPath/$wlsDomainName/nodemanager')
nmGenBootStartupProps('$wlsServerName')
disconnect()
EOF
}

#This function to check admin server status
function wait_for_admin() {
    #check admin server status
    count=1
    export CHECK_URL="http://$wlsAdminURL/weblogic/ready"
    status=$(curl --insecure -ILs $CHECK_URL | tac | grep -m1 HTTP/1.1 | awk {'print $2'})
    echo "Check admin server status"
    while [[ "$status" != "200" ]]; do
        echo "."
        count=$((count + 1))
        if [ $count -le 30 ]; then
            sleep 1m
        else
            echo "Error : Maximum attempts exceeded while checking admin server status"
            exit 1
        fi
        status=$(curl --insecure -ILs $CHECK_URL | tac | grep -m1 HTTP/1.1 | awk {'print $2'})
        if [ "$status" == "200" ]; then
            echo "WebLogic Server is running..."
            break
        fi
    done
}

# Create systemctl service for nodemanager
function createNodeManagerService() {
    echo "Setting CrashRecoveryEnabled true at $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties"
    sed -i.bak -e 's/CrashRecoveryEnabled=false/CrashRecoveryEnabled=true/g' $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties
    if [ $? != 0 ]; then
        echo "Warning : Failed in setting option CrashRecoveryEnabled=true. Continuing without the option."
        mv $wlsDomainPath/nodemanager/nodemanager.properties.bak $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties
    fi
    sudo chown -R $username:$groupname $wlsDomainPath/$wlsDomainName/nodemanager/nodemanager.properties*
    echo "Creating NodeManager service"
    # Added waiting for network-online service and restart service
    cat <<EOF >/etc/systemd/system/wls_nodemanager.service
[Unit]
Description=WebLogic nodemanager service
After=network-online.target
Wants=network-online.target
 
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
Restart=always
RestartSec=3
 
[Install]
WantedBy=multi-user.target
EOF
}

#This function to start managed server
function startManagedServer() {
    echo "Starting managed server $wlsServerName"
    cat <<EOF >$wlsDomainPath/start-server.py
connect('$wlsUserName','$wlsPassword','t3://$wlsAdminURL')
try:
   start('$wlsServerName', 'Server')
except:
   print "Failed starting managed server $wlsServerName"
   dumpStack()
disconnect()
EOF
    sudo chown -R $username:$groupname $wlsDomainPath
    runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; java $WLST_ARGS weblogic.WLST $wlsDomainPath/start-server.py"
    if [[ $? != 0 ]]; then
        echo "Error : Failed in starting managed server $wlsServerName"
        exit 1
    fi
}

# Create managed server setup
function createManagedSetup() {
    echo "Creating Managed Server Setup"
    cd $wlsDomainPath
    wget -q $weblogicDeployTool
    if [[ $? != 0 ]]; then
        echo "Error : Downloading weblogic-deploy-tool failed"
        exit 1
    fi
    sudo unzip -o weblogic-deploy.zip -d $wlsDomainPath
    echo "Creating managed server model files"
    create_managed_model
    create_machine_model
    create_ms_server_model
    echo "Completed managed server model files"
    sudo chown -R $username:$groupname $wlsDomainPath
    runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; $wlsDomainPath/weblogic-deploy/bin/createDomain.sh -oracle_home $oracleHome -domain_parent $wlsDomainPath  -domain_type WLS -model_file $wlsDomainPath/managed-domain.yaml"
    if [[ $? != 0 ]]; then
        echo "Error : Managed setup failed"
        exit 1
    fi
    wait_for_admin

    # For issue https://github.com/wls-eng/arm-oraclelinux-wls/issues/89
    getSerializedSystemIniFileFromShare

    echo "Adding machine to managed server $wlsServerName"
    runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; java $WLST_ARGS weblogic.WLST $wlsDomainPath/add-machine.py"
    if [[ $? != 0 ]]; then
        echo "Error : Adding machine for managed server $wlsServerName failed"
        exit 1
    fi
    echo "Adding managed server $wlsServerName"
    runuser -l oracle -c ". $oracleHome/oracle_common/common/bin/setWlstEnv.sh; java $WLST_ARGS weblogic.WLST $wlsDomainPath/add-server.py"
    if [[ $? != 0 ]]; then
        echo "Error : Adding server $wlsServerName failed"
        exit 1
    fi
}

function enabledAndStartNodeManagerService() {
    sudo systemctl enable wls_nodemanager
    sudo systemctl daemon-reload
    attempt=1
    while [[ $attempt -lt 6 ]]; do
        echo "Starting nodemanager service attempt $attempt"
        sudo systemctl start wls_nodemanager
        attempt=$(expr $attempt + 1)
        sudo systemctl status wls_nodemanager | grep running
        if [[ $? == 0 ]]; then
            echo "wls_nodemanager service started successfully"
            break
        fi
        sleep 3m
    done
}

function cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf $wlsDomainPath/managed-domain.yaml
    rm -rf $wlsDomainPath/weblogic-deploy.zip
    rm -rf $wlsDomainPath/weblogic-deploy
    rm -rf $wlsDomainPath/*.py
    echo "Cleanup completed."
}

function openPortsForCoherence() {
    # for Oracle Linux 7.3, 7.4, iptable is not running.
    if [ -z $(command -v firewall-cmd) ]; then
        return 0
    fi

    # for Oracle Linux 7.6, open weblogic ports
    echo "update network rules for managed server"
    sudo firewall-cmd --zone=public --add-port=$coherenceListenPort/tcp
    sudo firewall-cmd --zone=public --add-port=$coherenceListenPort/udp
    sudo firewall-cmd --zone=public --add-port=$storageListenPort/tcp

    sudo firewall-cmd --zone=public --add-port=$coherenceLocalport-$coherenceLocalportAdjust/tcp
    sudo firewall-cmd --zone=public --add-port=$coherenceLocalport-$coherenceLocalportAdjust/udp
    # Coherence TcpRing/IpMonitor  port 7
    sudo firewall-cmd --zone=public --add-port=7/tcp
    sudo firewall-cmd --zone=public --add-port=$nmPort/tcp

    sudo firewall-cmd --runtime-to-permanent
    sudo systemctl restart firewalld
}

# Mount the Azure file share on all VMs created
function mountFileShare() {
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
    if [[ $? != 0 ]]; then
        echo "Failed to mount //${storageAccountName}.file.core.windows.net/wlsshare $mountpointPath"
        exit 1
    fi
}

# Get SerializedSystemIni.dat file from share point to managed server vm
function getSerializedSystemIniFileFromShare() {
    runuser -l oracle -c "mv ${wlsDomainPath}/${wlsDomainName}/security/SerializedSystemIni.dat ${wlsDomainPath}/${wlsDomainName}/security/SerializedSystemIni.dat.backup"
    runuser -l oracle -c "cp ${mountpointPath}/SerializedSystemIni.dat ${wlsDomainPath}/${wlsDomainName}/security/."
    ls -lt ${wlsDomainPath}/${wlsDomainName}/security/SerializedSystemIni.dat
    if [[ $? != 0 ]]; then
        echo "Failed to get ${mountpointPath}/SerializedSystemIni.dat"
        exit 1
    fi
    runuser -l oracle -c "chmod 640 ${wlsDomainPath}/${wlsDomainName}/security/SerializedSystemIni.dat"
}

# main script starts from here

export SCRIPT_PWD=$(pwd)

# store arguments in a special array
args=("$@")
# get number of elements
ELEMENTS=${#args[@]}

# echo each element in array
# for loop
for ((i = 0; i < $ELEMENTS; i++)); do
    echo "ARG[${args[${i}]}]"
done

if [ $# -ne 18 ]; then
    usage
    exit 1
fi

export wlsDomainName=$1
export wlsUserName=$2
export wlsPassword=$3
export adminVMName=$4
export oracleHome=$5
export wlsDomainPath=$6
export storageAccountName=$7
export storageAccountKey=$8
export mountpointPath=$9
export enableWebLocalStorage=${10}
export enableELK=${11}
export elasticURI=${12}
export elasticUserName=${13}
export elasticPassword=${14}
export logsToIntegrate=${15}
export logIndex=${16}
export managedServerPrefix=${17}
export serverIndex=${18}

export clientClusterName="cluster1"
export coherenceClusterName="myCoherence"
export coherenceListenPort=7574
export coherenceLocalport=42000
export coherenceLocalportAdjust=42200
export groupname="oracle"
export nmHost=$(hostname)
export nmPort=5556
export storageClusterName="storage1"
export storageListenPort=7501
export weblogicDeployTool=https://github.com/oracle/weblogic-deploy-tooling/releases/download/weblogic-deploy-tooling-1.8.1/weblogic-deploy.zip
export username="oracle"
export wlsAdminT3ChannelPort=7005
export wlsAdminURL="${adminVMName}:${wlsAdminT3ChannelPort}"
export wlsCoherenceUnicastPortRange="-Dcoherence.localport=$coherenceLocalport -Dcoherence.localport.adjust=$coherenceLocalportAdjust"
export wlsServerTemplate="myServerTemplate"

if [ ${serverIndex} -eq 0 ]; then
    wlsServerName="admin"
else
    wlsServerName="${managedServerPrefix}${serverIndex}"
fi

validateInput
cleanup

if [ $wlsServerName == "admin" ]; then
    createCoherenceClusterModel
    cleanup
else
    installUtilities
    mountFileShare
    openPortsForCoherence
    updateNetworkRules
    createManagedSetup
    createNodeManagerService
    enabledAndStartNodeManagerService
    startManagedServer
    cleanup

    echo "enable ELK? ${enableELK}"
    chmod ugo+x ${SCRIPT_PWD}/elkIntegrationForConfiguredCluster.sh
    if [[ "${enableELK,,}" == "true" ]]; then
        echo "Set up ELK..."
        ${SCRIPT_PWD}/elkIntegrationForConfiguredCluster.sh \
            ${oracleHome} \
            ${wlsAdminURL} \
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
            ${managedServerPrefix}
    fi
fi
