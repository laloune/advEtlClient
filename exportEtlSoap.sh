#!/bin/bash
#read -p "ETL project: " project
#read -p "Username:" username
#read -s -p "Password:" password

username='admin'
password='admin'
project='sampleBiker'

url='http://localhost:7775/etlserver/services/ETL-Server/'

echo

#v7
#namespace='http://ns.jedox.com'
#v6
soapns='http://www.w3.org/2003/05/soap-envelope'
namespace='http://ns.jedox.com/ETL-Server'
axns='http://service.etl.jedox.com/xsd'
fileOut="./"$project".xml"
soapEnvBegin='<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:etl="'"$namespace"'"><soapenv:Header/><soapenv:Body>'
soapEnvEnd='</soapenv:Body></soapenv:Envelope>'

requestLogin="$soapEnvBegin"'<etl:login><etl:user>'"$username"'</etl:user><etl:password>'"$password"'</etl:password></etl:login>'"$soapEnvEnd"

callLogin=`wget $url -qO- --post-data "$requestLogin" --header "Content-Type: text/xml"`

sessId=`echo "$callLogin" | xmlstarlet sel -N soapns="$soapns" -N ns="$namespace" -N ax="$axns" -t -v "/soapenv:Envelope/soapenv:Body/ns:loginResponse/ns:return/ax:result"`

echo $sessId

# get all the components
# level 1

requestLocators="$soapEnvBegin"'<etl:getLocators><etl:locator>'"$project"'</etl:locator></etl:getLocators>'"$soapEnvEnd"

callLocators=`wget $url -qO- --post-data "$requestLocators" --header "Content-Type: text/xml" --header "etlsession:""$sessId"`

#echo $callLocators
echo '******'

# get number of nodes
nbNodes=`echo "$callLocators" | xmlstarlet sel -N soapns="$soapns" -N ns="$namespace" -t -v "count(//ns:return)"`

# begin to 3 to exclude functions and sources
for ((i=3;i<=$nbNodes-1;i++))
do
    topLocator=`echo "$callLocators" | xmlstarlet sel -N soapns="$soapns" -N ns="$namespace" -t -v "/soapenv:Envelope/soapenv:Body/ns:getLocatorsResponse/ns:return["$i"]"`
    
    # iterate on the locator's children components
    requestChildrenLocators="$soapEnvBegin"'<etl:getLocators><etl:locator>'"$topLocator"'</etl:locator></etl:getLocators>'"$soapEnvEnd"
    
    #echo "$requestChildrenLocators"
    
    callChildrenLocators=`wget $url -qO- --post-data "$requestChildrenLocators" --header "Content-Type: text/xml" --header "etlsession:""$sessId"`
    
    nbChildrenLocators=`echo "$callChildrenLocators" | xmlstarlet sel -N soapns="$soapns" -N ns="$namespace" -t -v "count(//ns:return)"`
    
    COUNTER=0
    #echo "$topLocator"': '"$nbChildrenLocators"
    for ((cLoc=1;cLoc<=$nbChildrenLocators;cLoc++))
    do
        childLocator=`echo "$callChildrenLocators" | xmlstarlet sel -N soapns="$soapns" -N ns="$namespace" -t -v "/soapenv:Envelope/soapenv:Body/ns:getLocatorsResponse/ns:return["$cLoc"]"`

        #echo "$childLocator"
        if [[ $childLocator =~ .*EO66* ]]
        then
            ((COUNTER++))
            echo "Candidate for deletion: $childLocator. Checking for dependencies..."
            # check dependencies
            requestDependencies="$soapEnvBegin"'<etl:getComponentDirectDependents><etl:locator>'"$childLocator"'</etl:locator></etl:getComponentDirectDependents>'"$soapEnvEnd"
            
            callDependencies=`wget $url -qO- --post-data "$requestDependencies" --header "Content-Type: text/xml" --header "etlsession:""$sessId"`
            
            nbDependencies=`echo "$callDependencies" | xmlstarlet sel -N soapns="$soapns" -N ns="$namespace" -N ax="$axns" -t -v "count(//ax:components)"`
            #echo "$childLocator"' nb dep: '$nbDependencies
            
            if [ $nbDependencies -gt 0 ]
            then     
                read -p "The locator $childLocator has $nbDependencies dependencies. Proceed ? [Y|n]: " ERASE

                case "$ERASE" in
                    "" | [Yy])
                        requestRemoveLocator="$soapEnvBegin"'<etl:removeComponents><etl:locators>'"$childLocator"'</etl:locators></etl:removeComponents>'"$soapEnvEnd"
                        callRemoveLocator=`wget $url -qO- --post-data "$requestRemoveLocator" --header "Content-Type: text/xml" --header "etlsession:""$sessId"`
                        
                        resultRemoveLocator=`echo "$callRemoveLocator" | xmlstarlet sel -N soapns="$soapns" -N ns="$namespace" -N ax="$axns" -t -v "/soapenv:Envelope/soapenv:Body/ns:removeComponentsResponse/ns:return/ax:result"`
                        echo "$resultRemoveLocator"                        
                    ;;
                    *)
                    echo "Aborting component deletion for locator $childLocator"
                    ;;
                esac
            else
                echo -en "The locator $childLocator has no dependencies. Removing component."
                
                requestRemoveLocator="$soapEnvBegin"'<etl:removeComponents><etl:locators>'"$childLocator"'</etl:locators></etl:removeComponents>'"$soapEnvEnd"
                callRemoveLocator=`wget $url -qO- --post-data "$requestRemoveLocator" --header "Content-Type: text/xml" --header "etlsession:""$sessId"`
                
                resultRemoveLocator=`echo "$callRemoveLocator" | xmlstarlet sel -N soapns="$soapns" -N ns="$namespace" -N ax="$axns" -t -v "/soapenv:Envelope/soapenv:Body/ns:removeComponentsResponse/ns:return/ax:result"`
                echo "$resultRemoveLocator"        
            fi            
        fi
    done
done

if [ $COUNTER -eq 0 ]
then
    echo "No component marked for deletion found. Did nothing"
fi
# disconnect

requestLogout="$soapEnvBegin"'<etl:logout><etl:etlsession>'"$sessId"'</etl:etlsession></etl:logout>'"$soapEnvEnd"

callLogout=`wget $url -qO- --post-data "$requestLogout" --header "Content-Type: text/xml" --header "etlsession:""$sessId"`






