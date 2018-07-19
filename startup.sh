#!/bin/bash
set -e
set -x

echo "Defining default values for ENVs..."
if [ "$CLUSTER_NAME" == "" ]; then
    echo "CLUSTER_NAME cannot be empty"
    exit 1
fi

if [ "$PEER_MONITOR_HOST" == "" ]; then
    echo "PEER_MONITOR_HOST cannot be empty"
    exit 1
fi

if ! grep '/var/lib/ceph/osd ' /proc/mounts; then
    echo "You have to mount volume '/var/lib/ceph/osd'. Example: mkfs.xfs /dev/ssd1; mount /dev/ssd1 /mnt/osd1; docker -v /mnt/osd1:/var/lib/ceph/osd. Exiting."
    exit 1
fi

echo "Creating ceph.conf..."
cat /ceph.conf.template | envsubst > /etc/ceph/ceph.conf
if [ "$OSD_EXT4_SUPPORT" == "true" ]; then
    echo "osd max object name len = 256" >> /etc/ceph/ceph.conf
    echo "osd max object namespace len = 64" >> /etc/ceph/ceph.conf
fi
cat /etc/ceph/ceph.conf

# if [ -z "$(ls -A ${/var/lib/ceph/osd})" ]; then
if [[ -n "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
    echo "Mounted OSD data dir is empty. Preparing and activating a new OSD..."

    UUID=$(uuidgen)

    while true; do
        ceph ping mon.* && break
        echo "Retrying to connect to peer monitor ${PEER_MONITOR_HOST} in 1 second..."
        sleep 1
    done

    ID=$(ceph osd new $UUID)
    echo "OSD created with ID ${ID}"

    OSD_PATH="/var/lib/ceph/osd/${CLUSTER_NAME}-${ID}"
    mkdir -p $OSD_PATH
    echo "Initializing OSD data dir ${OSD_PATH}..."
    ceph-osd --cluster "${CLUSTER_NAME}" -i "${ID}" --mkfs --osd-uuid "${UUID}"
    echo "New OSD created for OSD $CLUSTER_NAME-$ID" > /osd-initialization

else
    FOUND=0
    echo "Found data on mounted OSD data dir. Binding this OSD daemon to the OSD ID found in dir path."
    for ID in $(find /var/lib/ceph/osd -maxdepth 1 -mindepth 1 -name "${CLUSTER_NAME}*" | sed 's/.*-//'); do
        OSD_PATH="/var/lib/ceph/osd/${CLUSTER_NAME}-${ID}"
        echo "Checking osd path ${OSD_PATH}..."

        if [[ -n "$(find "$OSD_PATH" -prune -empty)" ]]; then
            echo "$OSD_PATH is empty. Ignoring it."
        else
            # check if the osd has a lock, if yes moving on, if not we run it
            # many thanks to Julien Danjou for the python piece
            # (piece of code extracted from github.com/ceph/ceph-container)
            if python -c "import sys, fcntl, struct; l = fcntl.fcntl(open('${OSD_PATH}/fsid', 'a'), fcntl.F_GETLK, struct.pack('hhllhh', fcntl.F_WRLCK, 0, 0, 0, 0, 0)); l_type, l_whence, l_start, l_len, l_pid, l_sysid = struct.unpack('hhllhh', l); sys.exit(0 if l_type == fcntl.F_UNLCK else 1)"; then
                echo "Data path $OSD_PATH is valid (seems to be populated and with no lock)"
                FOUND=1
                break
            else 
                echo "Data path $OSD_PATH is invalid (seems to be populated but has a lock - maybe another OSD daemon is using it)"
            fi
        fi
    done
    if [ $FOUND -eq 0 ]; then
        echo "Couldn't find a valid OSD path for binding this OSD daemon. Exiting."
        exit 1
    fi
fi

echo ""
echo "Starting OSD $CLUSTER_NAME-$ID at $OSD_PATH..."
ceph-osd -d --debug_osd $LOG_LEVEL --osd-data $OSD_PATH --id=$ID --cluster=$CLUSTER_NAME
