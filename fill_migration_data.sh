#!/bin/bash

# vmmigration API values variables
API_URL="vmmigration.googleapis.com"
API_VERSION="v1alpha1"

# GCP M4CE project data

MIGRATION_GROUP=test-group-curl1
GCP_MIGRATION_PROJECT=m4ce-manager-project
LOCATION=us-central1
SOURCE_ID=mtb-77


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

autofill_migration_default_values () {
CURRENT_VM_ID=$1
echo "######### Filling value for vm id $CURRENT_VM_ID "
update_migration_value $CURRENT_VM_ID 'vm_name' "\"$(get_vm_name_from_id $CURRENT_VM_ID |  tr '[:upper:]' '[:lower:]')\""
update_migration_value $CURRENT_VM_ID 'target_project' "\"app-target-1\""
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