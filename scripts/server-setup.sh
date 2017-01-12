#!/bin/sh

SERVER_NAME=$1
SERVER_DIR=/opt/mscs/server
SERVER_ARCHIVE="$SERVER_NAME-server-latest.tar.gz"
S3_BUCKET=$2
S3_PATH=s3://$S3_BUCKET/servers
WORK_DIR=/tmp/mscs

printError() {
    printf "ERROR $1\n"
    exit 1
}

[ -z "$SERVER_NAME" ] || printError "server name required"
[ -z "$S3_BUCKET" ] || printError "S3 bucket name required"

# if this is a first boot run, then server/ and tmp/ may not be created yet
mkdir -p $SERVER_DIR
mkdir -p $WORK_DIR

# sync latest copy of server files from s3
aws s3 sync --exclude "*" --include "$SERVER_ARCHIVE" $S3_PATH/ $WORK_DIR/

# make sure server files got here OK
[ -f "$WORK_DIR/$SERVER_ARCHIVE" ] || printError "fetching $SERVER_ARCHIVE"

# if our tmp work directory exists, then remove it
rm -rf $WORK_DIR/$SERVER_NAME

# extract world files into temp workspace
tar -C $WORK_DIR -xf $WORK_DIR/$SERVER_NAME-server-latest.tar.gz || printError "extracting $SERVER_ARCHIVE"

# Since we are resetting, remove server location if it exists
rm -rf $SERVER_DIR/$SERVER_NAME

# move new world over to disk
mv $WORK_DIR/$SERVER_NAME $SERVER_DIR/$SERVER_NAME
