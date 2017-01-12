#!/bin/sh

apt-get update
apt-get -y install git
clone https://github.com/seldonPlan/ephemeral-mc.git /opt/ephemeral-mc
chmod 744 /opt/ephemeral-mc/init-mc-instance.sh

/opt/ephemeral-mc/init-mc-instance.sh \
    --s3-bucket {{BUCKET_NAME}} \
    --world-name {{WORLD_NAME}} \
    --server {{SERVER_NAME}} \
    --mscs-enable-mirror {{1|0}} \
    --mscs-default-initial-memory {{MIN_MEM_IN_M}} \
    --mscs-default-maximum-memory {{MAX_MEM_IN_M}} \
    --mscs-log-duration 3 \
    --mscs-backup-duration 1