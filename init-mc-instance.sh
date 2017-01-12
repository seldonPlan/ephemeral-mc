#!/bin/sh

################################################################################
## SCRIPT LEVEL VARS
################################################################################

# script name
SCRIPT=$(basename $0)

# needed software packages
PKGS_JAVA="openjdk-8-jre-headless"
PKGS_MSCS_DEPS="perl libjson-perl python make wget rdiff-backup socat iptables"
PKGS_MISC="git awscli vim htop"

# script option argument variables
S3_BUCKET=
WORLD_NAME=
SERVER_NAME=
ARCHIVES_TO_KEEP=100
MIRROR_ENABLED=1

MSCS_REPO=https://github.com/MinecraftServerControl/mscs.git
MSCS_BRANCH=master
MSCS_HOME=/opt/mscs
MSCS_SRC=/opt/mscs-src
MSCS_TMP=/tmp/mscs
MSCS_TMP_DEFAULTS=$MSCS_TMP/mscs.defaults
MSCS_USER=minecraft

EPHMC_REPO=https://github.com/seldonPlan/ephemeral-mc.git
EPHMC_BRANCH=master
EPHMC_SRC=/opt/ephmc-src

################################################################################
## USAGE & ERROR HANDLING
################################################################################

usage() {
    cat <<EOF
Usage: $SCRIPT [OPTIONS]
Installs mscs on a debian-based server with sane administrative defaults

NOTE: Currently this script will install a PRE-EXISTING modded minecraft server
and world. The REQUIRED fields below identify which server and world to fetch
from S3

Options:

    --s3-bucket <bucket-name>
        (REQUIRED) AWS S3 bucket name for all remote storage operations
        format is the bucket name only (no 's3://', just the bucket name)

    --world-name <world-name>
        (REQUIRED) Name of the Minecraft world to restore or initialize
        defaults to "world"

    --server-name <server-target-name>
        (REQUIRED) Minecraft Server archive to setup on the machine
        defaults to the latest vanilla server

    --mscs-install-repo <repo>
        (OPTIONAL) Git repository to fetch the latest mscs version
        defaults to "https://github.com/MinecraftServerControl/mscs.git"

    --mscs-install-branch <branch>
        (OPTIONAL) Specific branch name within Git repository to fetch
        defaults to the "master" branch

    --mscs-* <global-server-property-value>
        (OPTIONAL) mscs global server properties with corresponding value
        all options entered here will be input along with their value,
        into an mscs.defaults file

    --ephmc-install-repo <repo>
        (OPTIONAL) Git repository to fetch the latest ephemeral-mc version
        defaults to "https://github.com/MinecraftServerControl/mscs.git"

    --ephmc-install-branch <branch>
        (OPTIONAL) Specific branch name within Git repository to fetch
        defaults to the "master" branch

    --archives-to-keep <number-of-archives>
        (OPTIONAL) The number of snapshot archives to keep in S3 for a world
        defaults to 100

EOF
}

printError() {
    printf "ERROR $1\n"
}

usageFail() {
    printError "$1"
    usage
    exit 1
}

execFail() {
    printError "$1 failed"
    exit 1
}

################################################################################
## INIT BLOCKS
################################################################################

# ensure system software dependencies are present and installed
setupSystemSoftware() {
    local PKGS PKG
    PKGS="$PKGS_JAVA $PKGS_MSCS_DEPS $PKGS_MISC"

    # Update existing system
    apt-get update || execFail "update"

    # not sure we should be doing an upgrade
    # apt-get -y upgrade || execFail "upgrade of system packages"

    for PKG in $PKGS; do
        apt-get -y install "$PKG" || execFail "install of $PKG"
    done
}

# create the `mscs.defaults` file in the temp workspace
initMscsDefaults() {
    mkdir -p "$MSCS_TMP"
    rm -f "$MSCS_TMP_DEFAULTS"
    touch "$MSCS_TMP_DEFAULTS"
}

# print value to `mscs.defaults`
printToMscsDefaults() {
    local PROPERTY VALUE
    PROPERTY=$1
    VALUE=$2

    echo "$PROPERTY=$VALUE" >> $MSCS_TMP_DEFAULTS
}

# install mscs.defaults
installMscsDefaults() {
    cp -t "$MSCS_HOME" "$MSCS_TMP_DEFAULTS"
}

# install minecraft server control script from git repo
installMscs() {
    git clone "$MSCS_REPO" --branch "$MSCS_BRANCH" "$MSCS_SRC" || execFail "clone of $MSCS_REPO at $MSCS_BRANCH"

    { cd /opt/mscs-src && make install; } || execFail "mscs install"
}

# install `ephemeral-mc` scripts from git repo
installEphemeralMc() {
    # must be run after a successful mscs install
    [ -d "$MSCS_HOME" ] || execFail "$MSCS_HOME not found, ephemeral-mc install"
    id "$MSCS_USER" >/dev/null 2>&1 || execFail "$MSCS_USER not found, ephemeral-mc install"

    # if the git directory exists, update it and switch to target branch
    if [ -d "$EPHMC_SRC" ] && [ -d "$EPHMC_SRC/.git" ]; then
        git -C "$EPHMC_SRC" fetch || execFail "git fetch in $EPHMC_SRC"
        git -C "$EPHMC_SRC" checkout "$EPHMC_BRANCH" || execFail "git checkout of $EPHMC_BRANCH in $EPHMC_SRC"
    else
        # remove the ephemeral-mc source dir if it exists
        rm -rf "$EPHMC_SRC"
        git clone "$EPHMC_REPO" --branch "$EPHMC_BRANCH" "$EPHMC_SRC" || execFail "clone of $EPHMC_REPO at $EPHMC_BRANCH"
    fi

    cp -R -t "$MSCS_HOME" "$EPHMC_SRC/scripts" || execFail "$EPHMC_SRC/scripts copy"
    chmod -R 755 "$MSCS_HOME/scripts" || execFail "$MSCS_HOME/scripts chmod"
    chown -R $MSCS_USER:$MSCS_USER "$MSCS_HOME/scripts" || execFail "$MSCS_HOME/scripts chown"
}

runEphemeralMcScript() {
    local RUN_SCRIPT
    RUN_SCRIPT="$MSCS_HOME/scripts/$1"

    shift
    [ -f "$RUN_SCRIPT" ] || execFail "$RUN_SCRIPT not found, ephemeral-mc setup"

    $RUN_SCRIPT ${1+"$@"}
}

# create crontab with appropriate args
installCrontab() {
    local BACKUP_CMD SYNC_CMD ARCHIVE_ROTATE_CMD
    local EVERY_FIVE_MIN EVERY_OTHER_HOUR EVERY_THIRTY_MINUTES
    local CRON_PATH

    CRON_PATH="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$MSCS_HOME/scripts"

    EVERY_FIVE_MIN='3-59/5 * * * *'
    EVERY_OTHER_HOUR='1 */2 * * *'
    EVERY_THIRTY_MINUTES='0,30 * * * *'

    BACKUP_CMD="[ -z \"\$(mscs ls running | grep $WORLD_NAME)\" ] && mscs backup $WORLD_NAME && $MSCS_HOME/scripts/archive_job.sh $WORLD_NAME $S3_BUCKET"
    SYNC_CMD="[ -z \"\$(mscs ls running | grep $WORLD_NAME)\" ] && mscs sync $WORLD_NAME"
    ARCHIVE_ROTATE_CMD="[ -z \"\$(mscs ls running | grep $WORLD_NAME)\" ] && $MSCS_HOME/scripts/s3_archive_rotation_job.sh $WORLD_NAME $ARCHIVES_TO_KEEP $S3_BUCKET"

    rm -f $MSCS_TMP/crontab

    echo "$CRON_PATH" > $MSCS_TMP/crontab
    echo "" >> $MSCS_TMP/crontab
    echo "$EVERY_THIRTY_MINUTES $BACKUP_CMD" >> $MSCS_TMP/crontab
    echo "$EVERY_OTHER_HOUR $ARCHIVE_ROTATE_CMD" >> $MSCS_TMP/crontab

    [ "$MIRROR_ENABLED" -eq "0" ] && echo "$EVERY_FIVE_MIN $SYNC_CMD" >> $MSCS_TMP/crontab

    cp "$MSCS_TMP"/crontab "$MSCS_HOME"/scripts/crontab
    crontab -u "$MSCS_USER" -r
    crontab -u "$MSCS_USER" "$MSCS_HOME/scripts/crontab"
}

################################################################################
## OPTION PARSING
################################################################################

isOpt() {
    case "$1" in
        --*)
            return 0
            ;;
    esac

    return 1
}


# Option parsing has been dumbed down to make it easier to process,
# the following should be true of every option:
#   - is long-form (ex. "--foo", as opposed to short-form "-f")
#   - has at least one argument (boolean opts too: true|false, yes|no, etc...)
parseOpts () {
    local OPT MSCS_DEF_OPT
    while [ ! -z "$1" ]; do
        OPT=$1

        # arguments are required for all options
        if $(isOpt $2); then
            usageFail "missing argument for [$OPT]"
        fi

        # process argument(s) to $OPT
        shift
        case "$OPT" in
            --s3-bucket )
                S3_BUCKET=$1
                ;;
            --world-name )
                WORLD_NAME=$1
                ;;
            --server-name )
                SERVER_NAME=$1
                ;;
            --mscs-install-repo )
                MSCS_REPO=$1
                ;;
            --mscs-install-branch )
                MSCS_BRANCH=$1
                ;;
            --mscs-* )
                case "$OPT" in
                    # special case MIRROR_ENABLED
                    --mscs-enable-mirror )
                        if [ "$1" -eq 0 ]; then
                            # in mscs.defaults, [0] indicates mirror DISABLED
                            MIRROR_ENABLED=1
                        elif [ "$1" -eq 1 ]; then
                            # in mscs.defaults, [1] indicates mirror ENABLED
                            MIRROR_ENABLED=0
                        else
                            usageFail "--mscs-enable-mirror 1 or 0"
                        fi
                        ;;
                    * )
                        :
                        ;;
                esac

                printToMscsDefaults $(echo $OPT | awk -F "--" '{print $2}') $1
                ;;
            --ephmc-install-repo )
                EPHMC_REPO=$1
                ;;
            --ephmc-install-branch )
                EPHMC_BRANCH=$1
                ;;
            --archives-to-keep )
                # tautology uses undocumented behavior fails when $1 is not an integer
                [ "$1" -eq "$1" ] 2>/dev/null || usageFail "--archives-to-keep must be a number"
                ARCHIVES_TO_KEEP=$1
                ;;
            * )
                usageFail "unknown option [$OPT]"
                ;;
        esac

        # shift to the next unparsed option
        shift
    done

    [ -z "$S3_BUCKET" ] && usageFail "--s3-bucket is a required option"
    [ -z "$WORLD_NAME" ] && usageFail "--world-name is a required option"
    [ -z "$SERVER_NAME" ] && usageFail "--server-name is a required option"
}

################################################################################
## SCRIPT WORKFLOW
################################################################################

initMscsDefaults
parseOpts $*
setupSystemSoftware
installMscs
installEphemeralMc
runEphemeralMcScript "server-setup.sh" "$WORLD_NAME" "$S3_BUCKET"
runEphemeralMcScript "world-setup.sh" "$WORLD_NAME" "$S3_BUCKET"
installMscsDefaults
installCrontab
