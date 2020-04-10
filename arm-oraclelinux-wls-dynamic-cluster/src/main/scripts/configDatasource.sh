#!/bin/bash
#---------------------------------------------------------------------------------------------------------------------------------- #
# This script is used to configure JDBC data source with Oracle jdbc driver for a given Weblogic server and Oracle Container Database.
# This script makes use of Weblogic REST URL to create datasource.
# Usage
# =====
#
# This shell can be used in one of the following way
# ./configDatasource.sh <wlsAdminHost> <wlsAdminPort> <wlsUserName> <wlsPassword> <jdbcDataSourceName> <dbConnectionURL> <dbUser> \ 
#                       <dbPassword>
# Provide dbConnectionURL in format 
#    jdbc:oracle:thin:@<db host name>:<db port>/<database name> or jdbc:oracle:thin:@<db host name>:<db port>:<database name>
# 
# Version 	: 1.0
# Date 		: 18 Feb 2020
# Author 	: sanjay.mantoor@oracle.com
#---------------------------------------------------------------------------------------------------------------------------------- #
export wlsAdminHost=$1
export wlsAdminPort=$2
export wlsUserName=$3
export wlsPassword=$4
export jdbcDataSourceName=$5
export dsConnectionURL=$6
export dsUser=$7
export dsPassword=$8
export wlsClusterName="cluster1"
export wlsAdminURL=$wlsAdminHost:$wlsAdminPort
export hostName=`hostname`
export restMGMTurl="http://$wlsAdminURL/management/weblogic/latest"
export restArgs=" -v --user $wlsUserName:$wlsPassword -H X-Requested-By:MyClient -H Accept:application/json -H Content-Type:application/json"

#Function to output message to StdErr
function echo_stderr ()
{
    echo "$@" >&2
}

#Function to display usage message
function usage()
{
  echo_stderr "./configDatasource.sh <wlsAdminHost> <wlsAdminPort> <wlsUserName> <wlsPassword> <jdbcDataSourceName> <dbConnectionURL> <dbUser> <dbPassword>"
  echo_stderr "Provide dsConnectionURL in format jdbc:oracle:thin:@<db host name>:<db port>/<database name>"
}

function checkSuccess(){
	checkResponse=`grep 'HTTP/1.1 200 OK\|HTTP/1.1 201 Created' out`
	if [[ $checkResponse == "" ]]; then
	    echo "==================================================================================="
		echo _stderr "REST executiion failed, response received"
		# Print the REST response received from last REST command executed
		cat out 
		echo "Reverting the changes"
		curl $restArgs -d {} -X POST $restMGMTurl/edit/changeManager/cancelEdit > out 2>&1
		echo "==================================================================================="
		echo "CONFIGURING JDBC DATA SOURCE FAILED"
		exit 1
	fi
}

function validateInput()
{

   if [ -z "$wlsAdminHost" ];
   then
       echo _stderr "Please provide WeblogicServer hostname"
       exit 1
   fi

   if [ -z "$wlsAdminPort" ];
   then
       echo _stderr "Please provide Weblogic admin port"
       exit 1
   fi

   if [ -z "$wlsUserName" ];
   then
       echo _stderr "Please provide Weblogic username"
       exit 1
   fi

   if [ -z "$wlsPassword" ];
   then
       echo _stderr "Please provide Weblogic password"
       exit 1
   fi

   if [ -z "$jdbcDataSourceName" ];
   then
       echo _stderr "Please provide JDBC datasource name to be configured"
       exit 1
   fi

   if [ -z "$dsConnectionURL" ];
   then
        echo _stderr "Please provide Oracle Database URL in the format 'jdbc:oracle:thin:@<db host name>:<db port>/<database name>'"
        exit 1
   fi

   if [ -z "$dsUser" ];
   then
       echo _stderr "Please provide Oracle Database user name"
       exit 1
   fi

   if [ -z "$dsPassword" ];
   then
       echo _stderr "Please provide Oracle Database password"
       exit 1
   fi

   if [ -z "$wlsClusterName" ];
   then
       echo _stderr "Please provide Weblogic target cluster name"
       exit 1
   fi

}


function createJDBCDataSource()
{
	echo "Creating JDBC data source with name $jdbcDataSourceName"
	echo "Executing startEdit command"
	curl $restArgs -d {} -X POST $restMGMTurl/edit/changeManager/startEdit > out 2>&1
	checkSuccess 
	echo "startEdit command executed successfully"
	echo "Creating JDBC system resource and set name"
	curl $restArgs -d '{ "name":"'"$jdbcDataSourceName"'", "targets": [ { "identity": [ "clusters", "'"$wlsClusterName"'"] } ]}' -X POST $restMGMTurl/edit/JDBCSystemResources?saveChanges=false > out 2>&1
	checkSuccess 
	echo "Creating JDBC system resource and setting name is successful"
	echo "Verifying JDBC system resource created"
	curl $restArgs -d '{ "name":"'"$jdbcDataSourceName"'"}' -X POST $restMGMTurl/edit/JDBCSystemResources/$jdbcDataSourceName/JDBCResource > out 2>&1
	checkSuccess
	echo "Verifying JDBC system resource is successful"
	echo "Configuring JDBC system resource's JNDI name"
	curl $restArgs -d '{ JNDINames: [ "'"$jdbcDataSourceName"'" ]}' -X POST $restMGMTurl/edit/JDBCSystemResources/$jdbcDataSourceName/JDBCResource/JDBCDataSourceParams > out 2>&1
	checkSuccess
	echo "Configuring JDBC system resource's JNDI name is successful"
	echo "Configuring the JDBC system resource's driver info"
	curl $restArgs -d '{driverName: 'oracle.jdbc.OracleDriver',url:"'"$dsConnectionURL"'",password:"'"$dsPassword"'"}' -X POST $restMGMTurl/edit/JDBCSystemResources/$jdbcDataSourceName/JDBCResource/JDBCDriverParams > out 2>&1
	checkSuccess
	echo "Configuring the JDBC system resource's driver info is successful" 
	echo "Configuring the JDBC system resource's driver property with user name"
	curl $restArgs -d '{name:  'user',value: "'"$dsUser"'"}'  -X POST $restMGMTurl/edit/JDBCSystemResources/$jdbcDataSourceName/JDBCResource/JDBCDriverParams/properties/properties > out 2>&1
	checkSuccess
	echo "Configuring the JDBC system resource's driver property with user name is successful"
	echo "Activating the changes"
	curl $restArgs -d '{}' -X POST $restMGMTurl/edit/changeManager/activate > out 2>&1
	checkSuccess
	echo "Activating the changes completed"
	echo "JDBC data source creation is completed"
}

if [ $# -ne 8 ]
then
    usage
    exit 1
fi

validateInput
createJDBCDataSource
