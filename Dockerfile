FROM flaviostutz/ceph-base:13.2.5

ENV CLUSTER_NAME 'ceph'
ENV PEER_MONITOR_HOST ''
ENV OSD_PUBLIC_IP ''
ENV OSD_CLUSTER_IP ''
ENV OSD_EXT4_SUPPORT false
ENV OSD_JOURNAL_SIZE 1024
ENV OSD_POOL_DEFAULT_SIZE 3
ENV OSD_POOL_DEFAULT_MIN_SIZE 2
ENV OSD_POOL_DEFAULT_PG_NUM 64
ENV OSD_CRUSH_CHOOSELEAF_TYPE 1
ENV OSD_CRUSH_WEIGHT 1
ENV OSD_CRUSH_LOCATION 'root=default'
ENV LOG_LEVEL 0

ADD startup.sh /
ADD ceph.conf.template /

VOLUME [ "/var/lib/ceph/osd" ]

CMD [ "/startup.sh" ]
