FROM flaviostutz/ceph-base:latest

ENV CLUSTER_NAME 'ceph'
ENV PEER_MONITOR_HOST ''
ENV OSD_NAME ''
ENV OSD_EXT4_SUPPORT false

ADD startup.sh /
ADD ceph.conf.template /

VOLUME [ "/var/lib/ceph/osd" ]

CMD [ "/startup.sh" ]
