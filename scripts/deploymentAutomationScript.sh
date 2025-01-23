#!/bin/bash


###### TO BE INSTALLED #######
#npm install -g anypoint-cli-v4
#sudo apt-get update && sudo apt-get -qq -y install jq  
#sudo apt install libxml2-utils
#wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
#chmod +x /usr/local/bin/yq



#### Parameters passed #####
# Argument 1 - Environment Name Ex: DEV
# Argument 2 - Anypoint Connected App Client ID
# Argument 3 - Anypoint Connected App Client Secret
# Argument 4 - Anypoint Org ID
# Argument 5 - Path to the pom.xml
# Argument 6 - Deployment type Ex: cloudhub
# Argument 7 - Action type: Allowed values: pre, post
# Argument 8 - Policies file reference: Ex: policies.yaml


#Anypoint Parameters
anypointEnv=$1
anypointClientId=$2
anypointClientSecret=$3
anypointOrgId=$4

#Additional Params
pomPath=$5
deploymentType=$6
deploymentActionType=$7
policyFilePath=$8

export ANYPOINT_CLIENT_ID=$anypointClientId
export ANYPOINT_CLIENT_SECRET=$anypointClientSecret
export ANYPOINT_ORG=$anypointOrgId
export ANYPOINT_ENV=$anypointEnv


#-------- BEGIN FUNCTIONS -------------
#Define function which captures assetId and version from source folder
captureAssetDetails() {

	#Capture assetId and version details from pom.xml
	assetId=`xmllint --xpath '/*[local-name()="project"]/*[local-name()="dependencies"]/*[local-name()="dependency"][*[local-name()="classifier"]="raml"]/*[local-name()="artifactId"]/text()' $pomPath`
	assetVersion=`xmllint --xpath '/*[local-name()="project"]/*[local-name()="dependencies"]/*[local-name()="dependency"][*[local-name()="classifier"]="raml"]/*[local-name()="version"]/text()' $pomPath`

	#Check for OAS specification if exists
	if [ "$assetId" == "" ]; then
		assetId=`xmllint --xpath '/*[local-name()="project"]/*[local-name()="dependencies"]/*[local-name()="dependency"][*[local-name()="classifier"]="oas"]/*[local-name()="artifactId"]/text()' $pomPath`
		assetVersion=`xmllint --xpath '/*[local-name()="project"]/*[local-name()="dependencies"]/*[local-name()="dependency"][*[local-name()="classifier"]="oas"]/*[local-name()="version"]/text()' $pomPath`
	fi
		echo "Asset Id in source code: $assetId"
		echo "Asset Version in source code: $assetVersion"

}

#Define function which creates API Instance ID

createAPIInstanceId() {

#Check if the script to be run for pre or post deployment

	if [ "$deploymentActionType" == "pre" ]; then
		#Conditional check - create api id if doesn't exist 
		if [ "$apiId" == "" ]; then
			apiId=$(anypoint-cli-v4 api-mgr:api:manage -m --deploymentType $deploymentType $assetId $assetVersion | cut -d':' -f2 | sed "s/ //g")
			echo "API instance doesn't exist. Creating one"

		elif [ $(echo -e "$apiManagerAssetVersion\n$assetVersion" | sort -V | head -n1) == "$apiManagerAssetVersion" ]; then
			anypoint-cli-v4 api-mgr:api:change-specification $apiId $assetVersion
			echo "API instance already exists. Changing the specification for $apiId"
		
		else
			echo "No change made to the api instance ID"
		fi

	fi
}


removePoliciesFun(){

	#Retrieve Remove policies List
	removePoliciesList=$(yq -o=json '.policies.remove' $policyFilePath | jq -r '.[]')

	echo "Remmove Policies List ::: $removePoliciesList"

	#Capture all the remove policies in an array
	removePolicies=()

	# Loop through the parsed JSON elements and add them to the array
	while read -r item; do
	  removePolicies+=("$item")
	done <<< "$removePoliciesList"


	#Iterate over removePolicies list
	for policy in "${removePolicies[@]}"
	do
		
		#Retrieve existing policies if exist with same name
		existingPolicy=`anypoint-cli-v4 api-mgr:policy:list -m $apiId | grep $policy`


		#Create policy if doesn't exist
		if [ "$existingPolicy" == "" ]; then
			echo "No policy exists to remove"

		else
			echo "Policy $policy already exists. Removing the policy"

			# Use cut to extract the policy instance Id; Edit the policy if already exists
			policyInstanceId=$(echo "$existingPolicy" | cut -d' ' -f2)

			output=`anypoint-cli-v4 api-mgr:policy:remove $apiId  $policyInstanceId`
		fi

	done

}

addUpdatePoliciesFun(){

	###### YAML Parser ############
	#Retrieve Add/Update policies List
	addUpdatePoliciesList=$(yq -o=json '.policies' $policyFilePath | jq -r '."add-update" | keys[]')

	echo "Add Update Policies List ::: $addUpdatePoliciesList"

	#Capture all the addUpdate policies in an array
	addUpdatePolicies=()

	# Loop through the parsed JSON elements and add them to the array
	while read -r item; do
	  addUpdatePolicies+=("$item")
	done <<< "$addUpdatePoliciesList"

	echo "Add Update Policies List ::: $addUpdatePolicies"

	#Iterate over addUpdatePolicies list
	for policy in "${addUpdatePolicies[@]}"
	do

		config=`yq '.policies."add-update".'$policy'.policyConfig' $policyFilePath | tr -d '\n' | sed 's/ //g' | sed 's/^"\(.*\)"$/\1/'`
		version=`yq -o=json '.policies."add-update".'$policy'.version' $policyFilePath | sed 's/"//g'`

		#Retrieve existing policies if exist with same name
		existingPolicy=`anypoint-cli-v4 api-mgr:policy:list -m $apiId | grep $policy`


		#Create policy if doesn't exist
		if [ "$existingPolicy" == "" ]; then

			output=`anypoint-cli-v4 api-mgr:policy:apply --config "$config" $apiId  $policy --policyVersion $version`

		else
			echo "Policy ${policyDetail[0]} already exists. Modifying the policy as per config"

			# Use cut to extract the policy instance Id; Edit the policy if already exists
			policyInstanceId=$(echo "$existingPolicy" | cut -d' ' -f2)

			output=`anypoint-cli-v4 api-mgr:policy:edit --config "$config" $apiId  $policyInstanceId`
		fi

	done

}

#-------- END FUNCTIONS -------------


#Step 1: Call function to capture asset details
captureAssetDetails 

#Step 2: Retrieve existing API instance ID if exists
if [ "$assetId" != "" ]; then

	apiId=$(anypoint-cli-v4 api-mgr:api:list --assetId $assetId --output json | jq '.[] | .id')
	apiManagerAssetVersion=$(anypoint-cli-v4 api-mgr:api:list --assetId $assetId --output json | jq '.[] | .assetVersion' | sed "s/\"//g")
	echo "Existing API Autodiscovery ID:  $apiId"
	echo "Asset Version in API Manager: $apiManagerAssetVersion"

#Step 3: Creates API Instance ID if the action is pre deployment
createAPIInstanceId

#Step 4: Check if the script to be run for pre or post deployment
if [ "$deploymentActionType" == "post" ]; then

	#Function which removes policies based on policies file
	removePoliciesFun

	#Function which adds or updates policies based on policies file
	addUpdatePoliciesFun

fi #End of POST check if

echo "APIId:$apiId"

fi #End of assetId check if
