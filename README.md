# ceph-osd
Docker image for running a Ceph OSD daemon

## Usage

* Prepare disks on host

```
mkfs.xfs /dev/sdb
mkdir -p /mnt/osd1-sdb
mount /dev/sdb /mnt/osd1-sdb
```

* docker-compose.yml

```
version: '3.5'

services:

  mon1:
    image: flaviostutz/ceph-monitor
    environment:
      - LOG_LEVEL=1

  osd1:
    build: .
    environment:
      - LOG_LEVEL=10
      - PEER_MONITOR_HOST=mon1
      - OSD_JOURNAL_SIZE=512
    volumes:
      - /mnt/sdb-osd1:/var/lib/ceph/osd

  osd2:
    build: .
    environment:
      - LOG_LEVEL=10
      - PEER_MONITOR_HOST=mon1
      - OSD_EXT4_SUPPORT=true
      - OSD_JOURNAL_SIZE=512
    volumes:
      - osd2:/var/lib/ceph/osd
      # this is just to show that you can use a regular Docker volume for testing purposes (need to enable 'ext4' support because of filename length restrictions)

volumes:
  osd2:
```

* run with "docker-compose up"

* perform some explorations

```
docker exec -it [instanceid of mon1] bash
bash> ceph -s
```
Look at OSD and Monitor status

### Todo
* Cephx auth support
* Journal support
