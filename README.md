# ceph-osd
Docker image for running a Ceph OSD daemon

## Usage

#### Minimal docker-compose.yml

* Considerations
  * doesn't expose OSD data path to host, so when the container instance is recreated, data is lost. ext4 is used for simplicity
  * Monitor and OSD daemon accessible just from the internal Docker network
  * very useful for demos and tests

* docker-compose.yml

```
version: '3.5'

services:

   etcd0:
    image: quay.io/coreos/etcd
    environment:
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd0:2379

  mon0:
    image: flaviostutz/ceph-monitor
    environment:
      - CREATE_CLUSTER=true
      - ETCD_URL=http://etcd0:2379

  osd1:
    image: flaviostutz/ceph-osd
    environment:
      - PEER_MONITOR_HOST=mon0
      - OSD_EXT4_SUPPORT=true
      - OSD_JOURNAL_SIZE=512
      - ETCD_URL=http://etcd0:2379

  osd2:
    image: flaviostutz/ceph-osd
    environment:
      - PEER_MONITOR_HOST=mon0
      - OSD_EXT4_SUPPORT=true
      - OSD_JOURNAL_SIZE=512
      - ETCD_URL=http://etcd0:2379

```

* run with "docker-compose up"
* perform some explorations

```
docker exec -it [instanceid of mon1] bash
bash> ceph -s
```
* Look at OSD and Monitor status

#### Exposed data docker-compose.yml

* Considerations
  * OSD data is mounted to a disk device
  * Monitor and OSD daemon exposed on the host interfaces, so they are accessible from the outside
  * more like a production deployment


* Prepare disks on host

```
mkfs.xfs /dev/sdb
mkdir -p /mnt/osd1-sdb
mount /dev/sdb /mnt/osd1-sdb

mkfs.xfs /dev/sdc
mkdir -p /mnt/osd2-sdc
mount /dev/sdb /mnt/osd2-sdc
```

* docker-compose.yml

```
version: '3.5'

services:

   etcd0:
    image: quay.io/coreos/etcd
    volumes:
      - etcd0:/etcd_data
    environment:
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd0:2379

  mon0:
    image: flaviostutz/ceph-monitor
    environment:
      - CREATE_CLUSTER=true
      - ETCD_URL=http://etcd0:2379

  mon1:
    image: flaviostutz/ceph-monitor
    environment:
      - PEER_MONITOR_HOST=mon0
      - ETCD_URL=http://etcd0:2379

  osd1:
    image: flaviostutz/ceph-osd
    environment:
      - PEER_MONITOR_HOST=mon0
      - ETCD_URL=http://etcd0:2379
    volumes:
      - /mnt/osd1-sdb:/var/lib/ceph/osd

  osd2:
    image: flaviostutz/ceph-osd
    environment:
      - PEER_MONITOR_HOST=mon0
      - ETCD_URL=http://etcd0:2379
    volumes:
      - /mnt/osd2-sdb:/var/lib/ceph/osd

```

* run with "docker-compose up"
* perform some explorations

```
docker exec -it [instanceid of mon1] bash
bash> ceph -s
```
Look at OSD and Monitor status


* host network mode for production OSDs

```

version: '3.5'

services:

  etcd0:
    image: quay.io/coreos/etcd
    ports:
      - 12379:2379
    environment:
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://${HOST_IP}:12379

  mon0:
    image: flaviostutz/ceph-monitor
    ports:
      - 16789:6789
    environment:
      - CREATE_CLUSTER=true
      - ETCD_URL=http://${HOST_IP}:12379
      - MONITOR_ADVERTISE_IP=${HOST_IP}
      - MONITOR_ADVERTISE_PORT=16789

  osd1:
    build: .
    network_mode: host
    environment:
      - LOG_LEVEL=0
      - PEER_MONITOR_HOST=${HOST_IP}:16789
      - OSD_EXT4_SUPPORT=true
      - OSD_JOURNAL_SIZE=512
      - ETCD_URL=http://${HOST_IP}:12379

  osd2:
    build: .
    network_mode: host
    environment:
      - PEER_MONITOR_HOST=${HOST_IP}:16789
      - OSD_EXT4_SUPPORT=true
      - OSD_JOURNAL_SIZE=512
      - ETCD_URL=http://${HOST_IP}:12379

  osd3:
    build: .
    network_mode: host
    environment:
      - PEER_MONITOR_HOST=${HOST_IP}:16789
      - OSD_EXT4_SUPPORT=true
      - OSD_JOURNAL_SIZE=512
      - ETCD_URL=http://${HOST_IP}:12379

```