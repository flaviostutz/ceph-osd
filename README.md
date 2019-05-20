# ceph-osd
Docker image for running a Ceph OSD daemon

Attention: You need to run this daemon in a machine running Kernel >= 4.5.2

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
    image: quay.io/coreos/etcd:v3.2.25
    environment:
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd0:2379

  mon0:
    image: flaviostutz/ceph-monitor
    pid: host
    environment:
      - CREATE_CLUSTER=true
      - ETCD_URL=http://etcd0:2379

  osd1:
    image: flaviostutz/ceph-osd
    pid: host
    environment:
      - PEER_MONITOR_HOSTS=mon0
      - OSD_EXT4_SUPPORT=true
      - OSD_JOURNAL_SIZE=512
      - ETCD_URL=http://etcd0:2379

  osd2:
    image: flaviostutz/ceph-osd
    pid: host
    environment:
      - PEER_MONITOR_HOSTS=mon0
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
Look at OSD and Monitor status



#### Simple Production OSD

* Considerations

  * OSD data is mounted to a disk device
  * Monitor and OSD daemon exposed on the host interfaces, so they are accessible from the outside
  * more like a production deployment

* Prepare disks on host

```
mkfs.xfs /dev/sda
mkdir -p /mnt/osd1-sda
mount /dev/sda /mnt/osd1-sda

mkfs.xfs /dev/sdb
mkdir -p /mnt/osd2-sdb
mount /dev/sdb /mnt/osd2-sdb

mkfs.xfs /dev/sdc
mkdir -p /mnt/osd3-sdc
mount /dev/sdc /mnt/osd2-sdc
```

* docker-compose.yml

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
    pid: host
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
    pid: host
    environment:
      - LOG_LEVEL=0
      - PEER_MONITOR_HOSTS=${HOST_IP}:16789
      - ETCD_URL=http://${HOST_IP}:12379
      # - OSD_PUBLIC_IP=${HOST_IP}
      # - OSD_CLUSTER_IP=${HOST_IP}
    volumes:
      - /mnt/osd1-sda:/var/lib/ceph/osd

  osd2:
    build: .
    network_mode: host
    pid: host
    environment:
      - PEER_MONITOR_HOSTS=${HOST_IP}:16789
      - ETCD_URL=http://${HOST_IP}:12379
    volumes:
      - /mnt/osd2-sdb:/var/lib/ceph/osd

  osd3:
    build: .
    network_mode: host
    pid: host
    environment:
      - PEER_MONITOR_HOSTS=${HOST_IP}:16789
      - ETCD_URL=http://${HOST_IP}:12379
    volumes:
      - /mnt/osd3-sdc:/var/lib/ceph/osd

```