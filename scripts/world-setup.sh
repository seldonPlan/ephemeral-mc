#!/bin/sh

WORLD_NAME=$1
WORLD_DIR=/opt/mscs/worlds
WORLD_ARCHIVE="$WORLD_NAME-world-latest.tar.gz"
MODS_ARCHIVE="$WORLD_NAME-mods-latest.tar.gz"
WORK_DIR=/tmp/mscs
S3_BUCKET=$2
S3_PATH=s3://$S3_BUCKET/worlds
HAS_MODS=0

printError() {
	printf "ERROR $1\n"
	exit 1
}

[ -z "$WORLD_NAME" ] && printError "world name required"
[ -z "$S3_BUCKET" ] && printError "S3 bucket name required"

# if this a first boot run, then worlds and tmp may not be created yet
mkdir -p $WORLD_DIR
mkdir -p $WORK_DIR

# sync latest copy of world files from s3
aws s3 sync --exclude "*" --include "$WORLD_NAME-*-latest.tar.gz" $S3_PATH/ $WORK_DIR/

# make sure world files got here OK
[ ! -f "$WORK_DIR/$WORLD_ARCHIVE" ] || printError "fetching $WORLD_ARCHIVE"

# may or may not have mods
if [ ! -f "$WORK_DIR/$MODS_ARCHIVE" ]; then
	printf "INFO $MODS_ARCHIVE not found\n"
	HAS_MODS=1
fi

# if our tmp work directory exists, then remove it
rm -rf $WORK_DIR/$WORLD_NAME

# extract world files into temp workspace
tar -C $WORK_DIR -xf $WORK_DIR/$WORLD_NAME-world-latest.tar.gz ||	printError "extracting $WORLD_ARCHIVE"

if [ "$HAS_MODS" -eq 0 ]; then
	tar -C $WORK_DIR -xf $WORK_DIR/$WORLD_NAME-mods-latest.tar.gz || printError "extracting $MODS_ARCHIVE"
fi

# Since we are resetting, remove on-disk and in-memory world if they exist
rm -rf $WORLD_DIR/$WORLD_NAME /dev/shm/mscs/$WORLD_NAME

# move new world over to disk
mv $WORK_DIR/$WORLD_NAME $WORLD_DIR/$WORLD_NAME
