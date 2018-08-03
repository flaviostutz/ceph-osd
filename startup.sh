#!/bin/bash
set -e
set -x


echo "Defining default values for ENVs..."
if [ "$CLUSTER_NAME" == "" ]; then
    echo "CLUSTER_NAME cannot be empty"
    exit 1
fi

if [ "$MONITOR_HOSTS" == "" ]; then
    echo "MONITOR_HOSTS must be defined"
    exit 1
fi

echo "Creating ceph.conf..."
cat /ceph.conf.template | envsubst > /etc/ceph/ceph.conf
if [ "$OSD_EXT4_SUPPORT" == "true" ]; then
    echo "osd max object name len = 256" >> /etc/ceph/ceph.conf
    echo "osd max object namespace len = 64" >> /etc/ceph/ceph.conf
fi

if [ "$MONITOR_HOSTS" != "" ]; then
    echo "mon host = ${MONITOR_HOSTS}" >> /etc/ceph/ceph.conf
fi

cat /etc/ceph/ceph.conf

resolveKeyring() {
    if [ -f /etc/ceph/keyring ]; then
        echo "Monitor key already known"
        return 0
    elif [ "$ETCD_URL" != "" ]; then 
        echo "Retrieving monitor key from ETCD..."
        KEYRING=$(etcdctl --endpoints $ETCD_URL get "/$CLUSTER_NAME/keyring")
        if [ $? -eq 0 ]; then
            echo $KEYRING > /tmp/base64keyring
            base64 -d -i /tmp/base64keyring > /etc/ceph/keyring
            return 0
        else
            return 2
        fi
    else
        echo "Monitor key doesn't exist and ETCD was not defined. Cannot retrieve keys."
        return 1
    fi
}

echo "Retrieving keyring for connecting to monitors..."
while true; do
    resolveKeyring && break
    if [ $? -eq 1 ]; then
        exit 2
    fi
    echo "Retrying in 1s..."
    sleep 1
done

if [[ -n "$(find /var/lib/ceph/osd -prune -empty)" ]]; then
    echo ">>> OSD data dir is empty. Preparing and activating a new OSD..."
    echo "Be sure to have prepared and mounted /var/lib/ceph/osd externaly. This is where the actual data for this OSD will be placed. Example: mkfs.xfs /dev/sdb; mount /dev/sdb /mnt/osd1; docker -v /mnt/osd1:/var/lib/ceph/osd."

    while true; do
        ceph mon dump && break
        echo "Retrying to connect to monitor ${MONITOR_HOSTS} in 1 second..."
        sleep 1
    done

    OSD_SECRET=$(ceph-authtool --gen-print-key)
    UUID=$(uuidgen)

    # echo "{\"cephx_secret\": \"$OSD_SECRET\"}" > /tmp/osdsecret
    # ID=$(ceph osd new $UUID -i /tmp/osdsecret -n client.admin -k /etc/ceph/keyring)
    ID=$(ceph osd new $UUID)
    echo "OSD created with ID ${ID}"

    OSD_PATH="/var/lib/ceph/osd/${CLUSTER_NAME}-${ID}"

    echo "Initializing OSD data dir ${OSD_PATH}..."
    mkdir -p $OSD_PATH
    cp /etc/ceph/keyring ${OSD_PATH}/keyring

    echo "Creating OSD key..."
    OSD_KEY=$(ceph auth get-or-create osd.${ID} osd 'allow *' mon 'allow rwx' -i ${OSD_PATH}/keyring)
    echo "${OSD_KEY}" >> ${OSD_PATH}/keyring
    # ceph auth ls

    echo "Preparing OSD data dir for BLUESTORE..."
    FSID=$(ceph mon dump | grep 'fsid' | cut -d ' ' -f 2)
    ceph-osd --cluster ${CLUSTER_NAME} --fsid $FSID -i $ID --mkfs --osd-uuid ${UUID} --osd-objectstore bluestore
    # ceph-osd --cluster "${CLUSTER_NAME}" -i "${ID}" --mkfs --osd-uuid "${UUID}"
    # echo "New OSD created for OSD $CLUSTER_NAME-$ID" > /osd-initialization

    echo "Adding newly created OSD to CRUSH map..."
    ceph osd crush add ${ID} ${OSD_CRUSH_WEIGHT} root=${OSD_CRUSH_LOCATION}

    echo "Creating 'default' pool if it doesn't exists yet..."
    ceph osd pool create default 32

else
    FOUND=0
    echo ">>> Found data on mounted OSD data dir. Binding this OSD daemon to the OSD ID found in dir path."
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

export LOCAL_IP=$(ip route get 8.8.8.8 | grep -oE 'src ([0-9\.]+)' | cut -d ' ' -f 2)
if [ "$OSD_PUBLIC_IP" == "" ]; then
    export OSD_PUBLIC_IP=LOCAL_IP
fi

echo "" >> /etc/ceph/ceph.conf
echo "[osd.$ID]" >> /etc/ceph/ceph.conf
echo "public addr = $OSD_PUBLIC_IP" >> /etc/ceph/ceph.conf
echo "cluster addr = $OSD_CLUSTER_IP" >> /etc/ceph/ceph.conf

echo ""
echo ">>> Starting OSD $CLUSTER_NAME-$ID at $OSD_PATH..."
ceph-osd -d --debug_osd $LOG_LEVEL --osd-data $OSD_PATH --id=$ID --cluster=$CLUSTER_NAME
