#!/bin/sh

WORLD_NAME=$1
S3_BUCKET=$2
S3_PATH=s3://$S3_BUCKET/worlds
WORK_DIR=/tmp/mscs/archived_backups
BACKUP_DIR=/opt/mscs/backups
BACKUP_ARCHIVE_NAME=$WORLD_NAME-world-$FILEDATE.tar.gz
LATEST_ARCHIVE_NAME=$WORLD_NAME-world-latest.tar.gz

# TODO: figure how to configure desired TZ
# FILEDATE="$(TZ='America/New_York' date +%Y%m%d%H%M%S)"
FILEDATE="$(date +%Y%m%d%H%M%S)"

printError() {
    printf "ERROR $1\n"
    exit 1
}

[ -z "$WORLD_NAME" ] && printError "world name required"
[ -z "$S3_BUCKET" ] && printError "S3 bucket name required"
[ ! -d "$BACKUP_DIR/$WORLD_NAME" ] && printError "source backups not found"

rm -rf $WORK_DIR
mkdir -p $WORK_DIR/$WORLD_NAME

rdiff-backup \
	-r now \
	--exclude **/mods \
	--exclude **/config \
	"$BACKUP_DIR/$WORLD_NAME" "$WORK_DIR/$WORLD_NAME" || printError "copying backup"

tar \
	-C $WORK_DIR \
	-czf $WORK_DIR/$BACKUP_ARCHIVE_NAME $WORLD_NAME || printError "archive creation"

aws s3 cp $WORK_DIR/$BACKUP_ARCHIVE_NAME "$S3_PATH/archive/$WORLD_NAME/$BACKUP_ARCHIVE_NAME"
aws s3 cp $WORK_DIR/$BACKUP_ARCHIVE_NAME "$S3_PATH/$LATEST_ARCHIVE_NAME"

rm -f $WORK_DIR/$BACKUP_ARCHIVE_NAME
