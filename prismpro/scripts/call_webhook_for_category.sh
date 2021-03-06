#!/bin/bash

PC_IP="$1"
PC_SSH_USER="$2"
PC_SSH_PASS="$3"
WEBHOOK_ID="$4"
CATEGORY_TYPE="$5"
CATEGORY_NAME="$6"
CATEGORY_VALUE="$7"

echo "Installing jq"
curl -k --show-error --remote-name --location https://s3.amazonaws.com/get-ahv-images/jq-linux64.dms
chmod u+x jq-linux64.dms
ln -s jq-linux64.dms jq
mv jq* ~/bin

ATTRIBUTE_NAME=""

ORIGINAL_CT=CATEGORY_TYPE

if [ "$CATEGORY_TYPE" == "vm" ]; then
    CATEGORY_TYPE="mh_vm"
    ATTRIBUTE_NAME="vm_name"
elif [ "$CATEGORY_TYPE" == "host" ]; then 
    CATEGORY_TYPE="host"
    ATTRIBUTE_NAME="node_name"
elif [ "$CATEGORY_TYPE" == "cluster" ]; then 
    CATEGORY_TYPE="cluster"
    ATTRIBUTE_NAME="cluster_name"
else
    echo "Incorrect category type" $CATEGORY_TYPE
    exit 0
fi

GROUPS_ENDPOINT="https://${PC_IP}:9440/api/nutanix/v3/groups"

REQUEST1=$(cat <<EOF
{
  "entity_type": "$CATEGORY_TYPE",
  "group_member_count": 500,
  "filter_criteria": "category_name==$CATEGORY_NAME;category_value==$CATEGORY_VALUE",
  "group_member_attributes": [
    {
      "attribute": "$ATTRIBUTE_NAME"
    }
  ]
}
EOF
)

echo "Request Body 1 :  $REQUEST1"

response=$(curl -X POST -k $GROUPS_ENDPOINT \
        --header 'Content-Type: application/json' \
        -u $PC_SSH_USER:$PC_SSH_PASS \
        --data-raw "$REQUEST1"      
        )    

len=$(jq -r  '.group_results[0].entity_results | length' <<< "${response}" ) 

len=$(( 10#$len ))
value=0
while [ $value -lt $len ]
do

echo "iterating $value"
entity_id=$(jq -r  ".group_results[0].entity_results["$value"].entity_id" <<< "${response}" ) 

echo "Entity ID $entity_id"

name=$(jq -r  ".group_results[0].entity_results["$value"].data[0].values[0].values[0]" <<< "${response}" ) 

echo "Name $name"

((value=value+1))

REQUEST2=$(cat <<EOF
{
 "trigger_type": "incoming_webhook_trigger",
 "trigger_instance_list": [{
   "webhook_id": "$WEBHOOK_ID",
   "entity1" : "{\"type\":\"$ORIGINAL_CT\",\"name\":\"$name\",\"uuid\":\"$entity_id\"}"
 }]
}


EOF
)

echo "$REQUEST2"

TRIGGER_ENDPOINT="https://${PC_IP}:9440/api/nutanix/v3/action_rules/trigger"
response=$(curl -X POST -k $TRIGGER_ENDPOINT \
        --header 'Content-Type: application/json' \
        -u $PC_SSH_USER:$PC_SSH_PASS \
        --data-raw "$REQUEST2" \
        )

echo "Updated successfully : $response"


done


exit 0

