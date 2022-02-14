#!/bin/bash

# vmmigration API values variables
API_URL="vmmigration.googleapis.com"
#API_VERSION="v1alpha1"
API_VERSION="v1"
# GCP M4CE project data


# M4CE GCP project 
MIGRATION_GROUP=test-group-curl1
GCP_MIGRATION_PROJECT=m4ce-manager-project
LOCATION=us-central1
SOURCE_ID=mtb-58      

INPUT_CSV_LEVEL=Migrate_Runbook.csv

declare -a CSV_HEADER=()
declare -a CURRENT_MIGRATED=()

fill_csv_header () {
    for current_item in $(head -1 $INPUT_CSV_LEVEL | tr ',' '\n') ; do
        CSV_HEADER+=( "$current_item" )
    done 
}

get_column_number_for_field () {
    head -1 $INPUT_CSV_LEVEL > csv_header.csv
    awk -F ',' -v key="$1" '{ for (i=1; i<=NF; ++i) { print $i ; if ($i == key)  i key } }' csv_header.csv
}

fill_migration_values() {
    VM_NAME=$1
    VM_FILE="./mappings/$VM_NAME"

    CURRENT_VM_ID=$(grep VmID ./mappings/$VM_NAME | awk -F ',' '{print $2}')

    ## Convert the M4CE V4 CSV based values to the M4CE V5 values

    # Get the VM name from the M4CE API - set to lower case is mandatory for GCE naming restrictions
    update_migration_value $CURRENT_VM_ID 'vm_name' "\"$(get_vm_name_from_id $CURRENT_VM_ID |  tr '[:upper:]' '[:lower:]')\""

    # Get the project from the CSV, and assume the target project was already added as the target project
    TARGET_GCP_PROJECT=$(grep GcpProject $VM_FILE | awk -F ',' '{print $2}')
    update_migration_value $CURRENT_VM_ID 'target_project' "\"projects/$GCP_MIGRATION_PROJECT/locations/global/targetProjects/$TARGET_GCP_PROJECT\""    
    
    # Set the zone - cannot be taken from the csv template
    update_migration_value $CURRENT_VM_ID 'zone' "\"us-central1-a\""

    # Get the VM sizing from teh CSV - extract the type serie from the name of the machine type
    
    TARGET_MACHINE_TYPE=$(grep TargetInstanceType $VM_FILE | awk -F ',' '{print $2}')
    TARGET_MACHINE_TYPE_SERIES=$(echo $TARGET_MACHINE_TYPE | awk -F '-' '{print $1}')

    update_migration_value $CURRENT_VM_ID 'machine_type_series' "\"$TARGET_MACHINE_TYPE_SERIES\""
    update_migration_value $CURRENT_VM_ID 'machine_type' "\"$TARGET_MACHINE_TYPE\""

    # Generate a string array from the csv input
    TAG_LIST="["
    
    for CURRENT_TAG in $(grep GcpNetworkTags $VM_FILE | awk -F ',' '{$1=""}1' | tr -d "\"")
    do
        TAG_LIST="$TAG_LIST\"$CURRENT_TAG\","
    done
    echo ${TAG_LIST:0:$((${#TAG_LIST}-1))}"]"
    update_migration_value $CURRENT_VM_ID 'network_tags' "$TAG_LIST"

    # if BYOL is in the os license string, use the BYOl value
    
    TARGET_LICENSE_TYPE="COMPUTE_ENGINE_LICENSE_TYPE_DEFAULT"
 
    update_migration_value $CURRENT_VM_ID 'license_type' "\"$TARGET_LICENSE_TYPE\""

    # Fetch the network interface details from the subnet value and create a dict structure for the vmmigration API call

    TARGET_SUBNET_URL=$(grep TargetSubnet $VM_FILE | awk -F ',' '{print $2}')
   
    if [[ $TARGET_SUBNET_URL != *https://www.googleapis.com* ]] ; then TARGET_SUBNET_URL="https://www.googleapis.com/compute/v1/$TARGET_SUBNET_URL" ;  fi

    TARGET_NETWORK_URL=$(curl -X GET -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" $TARGET_SUBNET_URL | grep '"network"' | awk -F "\"" '{print $4}')
    
    TARGET_NETWORK_VALUE=$(echo "$TARGET_NETWORK_URL" | sed 's:.*networks/::')
    TARGET_SUBNET_VALUE=$(echo "$TARGET_SUBNET_URL" | sed 's:.*v1/::')

    update_migration_value $CURRENT_VM_ID 'network_interfaces' "{ network : \"$TARGET_NETWORK_VALUE\" , subnetwork : \"$TARGET_SUBNET_URL\" }"

    # get the service account - the quote are tipically already present in the csv so they are not added when calling the function

    TARGET_SA=$(grep GcpInstanceServiceAccount $VM_FILE | awk -F ',' '{print $2}')
    update_migration_value $CURRENT_VM_ID 'service_account' "$TARGET_SA"

    # 
    TARGET_DISK_CSV_VALUE=$(grep GcpDiskType $VM_FILE | awk -F ',' '{print $2}')
    case $TARGET_DISK_CSV_VALUE in

        SSD)
            update_migration_value $CURRENT_VM_ID 'disk_type' "\"COMPUTE_ENGINE_DISK_TYPE_SSD\""
        ;;
        balanced)
            update_migration_value $CURRENT_VM_ID 'disk_type' "\"COMPUTE_ENGINE_DISK_TYPE_BALANCED\""
        ;;
        *)
            update_migration_value $CURRENT_VM_ID 'disk_type' "\"COMPUTE_ENGINE_DISK_TYPE_STANDARD\""
        ;;
    esac

     update_migration_value $CURRENT_VM_ID 'labels' '{ label1 : "labelvalue1" , label2 : "labelvalue2" }'

    echo "######### Filling value for vm id $CURRENT_VM_ID "
   

   
    
    update_migration_value $CURRENT_VM_ID 'labels' '{ label1 : "labelvalue1" , label2 : "labelvalue2" }'
    update_migration_value $CURRENT_VM_ID 'compute_scheduling' '{ on_host_maintenance : "MIGRATE" , restart_type : "AUTOMATIC_RESTART" }'
    update_migration_value $CURRENT_VM_ID 'boot_option' "\"COMPUTE_ENGINE_BOOT_OPTION_BIOS\""

}


## M4CE csv parser requires being able to read a csv file, with potential nested string with comma parameters (which causes a simple awk parse tonot do the trick)
parse_m4ce_v4_csv () {
    IFS=$'\n'
    while read CURRENT_LINE ; do
        CSV_FIELD_COUNTER=0
        echo "parsing line $CURRENT_LINE"
        CURRENT_FIELD=""
        NESTED_STRING_BOOLEAN=false
        CURRENT_VM_NAME=""
        TMP_VALUE_FILE_NAME="./mappings/tmp_value_file"
        echo "" > $TMP_VALUE_FILE_NAME
        for CURRENT_CHAR in $(echo $CURRENT_LINE | grep -o . ); do
            #echo "current char" $CURRENT_CHAR " in nested string " $NESTED_STRING_BOOLEAN
            if [[ "$CURRENT_CHAR" == "," && $NESTED_STRING_BOOLEAN == false ]]
            then
                    echo "FIELD  ${CSV_HEADER[$CSV_FIELD_COUNTER]} is $CURRENT_FIELD"
                    if [[ "${CSV_HEADER[$CSV_FIELD_COUNTER]}" == "TargetInstanceName" ]]
                    then
                        CURRENT_VM_NAME="$CURRENT_FIELD"
                        echo "VM name detected : $CURRENT_FIELD"
                    fi
                    echo "${CSV_HEADER[$CSV_FIELD_COUNTER]},$CURRENT_FIELD" >> $TMP_VALUE_FILE_NAME
                    let CSV_FIELD_COUNTER++
                    CURRENT_FIELD=""
                
            else 
                if [[ "$CURRENT_CHAR" == "\"" && $NESTED_STRING_BOOLEAN == false ]]
                then
                    #echo "nested string found"
                    NESTED_STRING_BOOLEAN=true
                else
                    if [[ "$CURRENT_CHAR" == "\"" ]]
                    then
                        NESTED_STRING_BOOLEAN=false
                        #echo "end of nested string"
                    fi
                fi
                CURRENT_FIELD="$CURRENT_FIELD$CURRENT_CHAR"
            fi
        done
        mv $TMP_VALUE_FILE_NAME "./mappings/$CURRENT_VM_NAME"
    done < $INPUT_CSV_LEVEL
    unset IFS
}
fill_csv_header
parse_m4ce_v4_csv
exit 0

get_migration_values () {
    CURRENT_VM_ID=$1
    curl -X GET \
-H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
https://$API_URL/$API_VERSION/projects/$GCP_MIGRATION_PROJECT/locations/$LOCATION/sources/$SOURCE_ID/migratingVms/$CURRENT_VM_ID
}

get_vm_id_from_name () {
    VM_DISPLAY_NAME=$1
    curl -X GET \
    -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
    https://$API_URL/$API_VERSION/projects/$GCP_MIGRATION_PROJECT/locations/$LOCATION/sources/$SOURCE_ID/migratingVms/ | jq --arg VM_DISPLAY_NAME "$VM_DISPLAY_NAME" '.migratingVms[] | select(.displayName==$VM_DISPLAY_NAME)' | jq '.sourceVmId' | tr -d "\""

}

get_vm_name_from_id() {
    CURRENT_VM_ID=$1
    curl -X GET \
    -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
    https://$API_URL/$API_VERSION/projects/$GCP_MIGRATION_PROJECT/locations/$LOCATION/sources/$SOURCE_ID/migratingVms/$CURRENT_VM_ID | jq '.displayName' | tr -d "\""

}

get_all_vm_names () {
    curl -X GET -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" https://$API_URL/$API_VERSION/projects/$GCP_MIGRATION_PROJECT/locations/$LOCATION/sources/$SOURCE_ID/migratingVms/ | jq '.migratingVms[] | .displayName' | tr -d "\""

}

get_all_vm_ids () {
    
    curl -X GET -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" https://$API_URL/$API_VERSION/projects/$GCP_MIGRATION_PROJECT/locations/$LOCATION/sources/$SOURCE_ID/migratingVms/ | jq '.migratingVms[] | .sourceVmId' | tr -d "\""

}

## Arg #1 is the name of the value to update
## Arg #2 is value to set
## Example : update_migration_value 'license_type' 'COMPUTE_ENGINE_LICENSE_TYPE_PAYG'
update_migration_value () {
    CURRENT_VM_ID=$1
    KEY_TO_UPDATE=$2
    VALUE_TO_UPDATE=$3
    echo "update value $KEY_TO_UPDATE to $VALUE_TO_UPDATE"
    curl -X PATCH \
-H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
https://$API_URL/$API_VERSION/projects/$GCP_MIGRATION_PROJECT/locations/$LOCATION/sources/$SOURCE_ID/migratingVms/$CURRENT_VM_ID?update_mask=compute_engine_target_defaults.$KEY_TO_UPDATE \
-H 'Content-Type: application/json' \
--data "{compute_engine_target_defaults: { $KEY_TO_UPDATE: $VALUE_TO_UPDATE}}"
}

simple_get_from_csv () {
    KEY=$1

}

autofill_migration_default_values () {
CURRENT_VM_ID=$1
echo "######### Filling value for vm id $CURRENT_VM_ID "
update_migration_value $CURRENT_VM_ID 'vm_name' "\"$(get_vm_name_from_id $CURRENT_VM_ID |  tr '[:upper:]' '[:lower:]')\""
update_migration_value $CURRENT_VM_ID 'target_project' "\"projects/m4ce-manager-project/locations/global/targetProjects/app-target-1\""
update_migration_value $CURRENT_VM_ID 'project' "\"app-target-1\""
update_migration_value $CURRENT_VM_ID 'zone' "\"us-central1-a\""
update_migration_value $CURRENT_VM_ID 'machine_type_series' "\"n1\""
update_migration_value $CURRENT_VM_ID 'machine_type' "\"n1-standard-1\""
update_migration_value $CURRENT_VM_ID 'network_tags' '["testtag1", "testtag2"]'
update_migration_value $CURRENT_VM_ID 'license_type' "\"COMPUTE_ENGINE_LICENSE_TYPE_DEFAULT\""
update_migration_value $CURRENT_VM_ID 'network_interfaces' '{ network : "network-target-1" , subnetwork : "projects/network-target-1/regions/us-central1/subnetworks/us-central1-subnet" }'
update_migration_value $CURRENT_VM_ID 'service_account' "\"custom-default-sa@app-target-1.iam.gserviceaccount.com\""
update_migration_value $CURRENT_VM_ID 'disk_type' "\"COMPUTE_ENGINE_DISK_TYPE_STANDARD\""
update_migration_value $CURRENT_VM_ID 'labels' '{ label1 : "labelvalue1" , label2 : "labelvalue2" }'
update_migration_value $CURRENT_VM_ID 'compute_scheduling' '{ on_host_maintenance : "MIGRATE" , restart_type : "AUTOMATIC_RESTART" }'
update_migration_value $CURRENT_VM_ID 'boot_option' "\"COMPUTE_ENGINE_BOOT_OPTION_BIOS\""
}

get_all_vm_ids
for CURRENT_MIGRATING_ID in $(get_all_vm_ids); do
    echo "fetch values for $CURRENT_MIGRATING_ID "
    #get_vm_name_from_id $CURRENT_MIGRATING_ID
    autofill_migration_default_values $CURRENT_MIGRATING_ID
    get_migration_values $CURRENT_MIGRATING_ID
done

parse_array () {
    VALUES_DICT=$1
    echo ${VALUES_DICT[a]}
    for sound in "${!VALUES_DICT[@]}"; do 
        echo "$sound - ${VALUES_DICT[$sound]}"; 
    done
}



