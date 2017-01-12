#!/bin/sh

WORLD_NAME=$1
KEEPCOUNT=$2
S3_BUCKET=$3
S3_PATH=s3://$S3_BUCKET/worlds/archive/$WORLD_NAME
TMP_PATH=/tmp/mscs
WORK_FILE=$TMP_PATH/s3ls.txt
TEMP_FILE=$TMP_PATH/s3ls.tmp.txt
LINECOUNT=

printError() {
    printf "ERROR $1\n"
    exit 1
}

[ -z "$WORLD_NAME" ] && printError "world name required"
[ -z "$KEEPCOUNT" ] && printError "number of files to keep required"
[ -z "$S3_BUCKET" ] && printError "S3 bucket name required"

# fetch the list of files from s3
rm -f $WORK_FILE $TEMP_FILE
mkdir -p $TMP_PATH
aws s3 ls $S3_PATH/ > $WORK_FILE || printError "aws s3 ls command unsuccessful"

# remove empty entry in ls listing if it exists
if [ -z $(awk 'NR==1{print $4}' $WORK_FILE) ]; then
    tail -n +2 $WORK_FILE > $TEMP_FILE
    cat $TEMP_FILE > $WORK_FILE
fi

# if there aren't more files than we want to keep then we can exit successfully
LINECOUNT=$(cat $WORK_FILE | wc -l)
if [ "$LINECOUNT" -le "$KEEPCOUNT" ]; then
    printf "INFO found $LINECOUNT file(s) in s3 bucket($S3_PATH), keeping up to $KEEPCOUNT file(s)\n"
    exit 0
fi

# sort file in place so that oldest entries appear at the top of the file
sort -o $WORK_FILE $WORK_FILE

# remove all valid entries, leaving only entries to remove
head -n $(( $LINECOUNT - $KEEPCOUNT )) $WORK_FILE > $TEMP_FILE
awk '{ print $4  }' $TEMP_FILE > $WORK_FILE

# remove files that we found we no longer need
while read FILE;
    	do printf "INFO removing $FILE \n";
    	aws s3 rm "$S3_PATH/$FILE"
done < $WORK_FILE

rm -f $WORK_FILE $TEMP_FILE
