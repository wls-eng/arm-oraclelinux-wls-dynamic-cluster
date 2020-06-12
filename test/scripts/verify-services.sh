# Verify the service using systemctl status
function verifyServiceStatus()
{
  serviceName=$1
  systemctl status rngd | grep "active (running)"    
  if [[ $? != 0 ]]; then
     echo "$serviceName is not in active (running) state"
     exit 1
  fi
  echo "$serviceName is active (running)"
}

#Verify the service using systemctl is-active
function verifyServiceActive()
{
  serviceName=$1
  state=$(systemctl is-active $serviceName)
  if [[ $state == "active" ]]; then
     echo "$serviceName is active"
  else
     echo "$serviceName is not active"
     exit 1
  fi
}

# Pass yes/no
export isAdminServer=$1
if [[ $isAdminServer == "yes" ]]; then
  echo "Testing on admin server"
  servicesList="rngd wls_nodemanager wls_admin"
else
  echo "Testing on managed server"
  servicesList="rngd wls_nodemanager"
fi

for service in $servicesList
do
   verifyServiceStatus $service
   verifyServiceActive $service
done

exit 0

