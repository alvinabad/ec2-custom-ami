#!/bin/bash

STATUS_FILE=/tmp/aws_ec2.$RANDOM

usage() {
    cat <<EOF
Usage:
    `basename $0` volume-id
EOF
    exit 1
}

cleanup() {
    if [ -n "$SNAPSHOT_ID" ]; then
        #aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID
        true
    fi
    rm -f $STATUS_FILE
}

abort() {
    echo "ERROR: $*" 1>&2
    cleanup
    exit 1
}

trap "cleanup; exit 1" SIGHUP SIGINT SIGTERM

create_snapshot() {
    [ -z "$VOLUME_ID" ] && usage

    aws ec2 create-snapshot --volume-id $VOLUME_ID \
        --description "myubuntu" | tee $STATUS_FILE

    SNAPSHOT_ID=`awk '{print $4}' $STATUS_FILE`
    STATUS=`awk '{print $6}' $STATUS_FILE`
    PERCENT="0%"

    while [ "$STATUS" != "completed" ]
    do
        echo "$SNAPSHOT_ID: $STATUS, $PERCENT"
        sleep 5
        aws ec2 describe-snapshots --snapshot-id $SNAPSHOT_ID | tee $STATUS_FILE
        STATUS=`awk '{print $8}' $STATUS_FILE`
        PERCENT=`awk '{print $5}' $STATUS_FILE`
    done
}

create_image() {
    [ -z "$SNAPSHOT_ID" ] && usage

set -x
    aws ec2 register-image \
        --name "Example_Image_Name" \
        --description "Example Image Description" \
        --architecture x86_64 \
        --kernel-id aki-920531d7 \
        --root-device-name "/dev/sda" \
        --block-device-mappings "[
           {
             \"DeviceName\": \"/dev/sda\",
             \"Ebs\": {
             \"SnapshotId\": \"$SNAPSHOT_ID\",
             }
           }
        ]"
}

create_image2() {
    [ -z "$SNAPSHOT_ID" ] && usage

    echo --------------------------------------------------------------------------------
    echo generate-cli-skeleton
    aws ec2 register-image --generate-cli-skeleton
    echo --------------------------------------------------------------------------------

    cat > /tmp/x.json <<EOF
{
    "DryRun": false,
    "Name": "myubuntu",
    "Description": "myubuntu",
    "Architecture": "x86_64",
    "KernelId": "aki-920531d7",
    "RootDeviceName": "/dev/sda",
    "BlockDeviceMappings": [
        {
            "Ebs": {
                "SnapshotId": "$SNAPSHOT_ID",
            },
            "DeviceName": "/dev/sda1",
        }
    ]
}
EOF

#    "VirtualizationType": "",
#    "SriovNetSupport": ""

    cat /tmp/x.json
    echo --------------------------------------------------------------------------------
    aws ec2 register-image --cli-input-json file:///tmp/x.json
}


ARG=$1
# Create snapshot
VOLUME_ID=$ARG
create_snapshot 

# Create image
[ -n "$SNAPSHOT_ID" ] || SNAPSHOT_ID=$ARG
#create_image
