#!/usr/bin/env bash

# This gets copied into a container image and run.  Multiple repos are
# pulled from Github and Debian packages created from them.  The
# resulting .deb files are deposited in the "debs" volume from the
# "docker run" command.  Log files for each package build can also be
# found there.  The script is then copied into an architectural chroot
# and run again,  with bind mounts providing the same global paths.

# This script uses git-build-package and depends on a "debian/gbp.conf"
# in one branch of each repo.  Right now the repos are disjoint as to
# which branch has what, but unification is underway.

# SUPPRESSXXX is usually for debugging, skipping things that work and
# saving time to reach broken things faster.  The variables are executed at
# runtime and resolve to /bin/[true|false].  Packages are always downloaded
# but may not be built: docker run ..... -e SUPPRESSXXX=true l4fame-build
# Time savings are based on using 90 cores iton parallel builds.

export SUPPRESSAMD=${SUPPRESSAMD:-false}	# saves 45 minutes
export SUPPRESSARM=${SUPPRESSARM:-false}	# in chroot; saves 1 hour
export SUPPRESSKERNEL=${SUPPRESSKERNEL:-false}	# 5-8 minutes AMD, 45 ARM

# Override optimizations that might skip building.  There aren't many.
export FORCEBUILD=${FORCEBUILD:-true}

set -u

# Global directories

readonly ALLGITS=/allgits		# "git clone" here
readonly DEBS=/debs			# Container<->host gateway
readonly GBPOUT=/gbp-build-area		# "gbp --git-export-dir" and *.deb

###########################################################################
# Convenience routines.  Can't call them in early execution until their
# "private" globals have been set.

readonly LOGDIR=$DEBS/logs		# Per-architecture
declare -i LOGSEQ=1			# Sequence number for child logs
readonly MASTERLOG=00_mainloop.log	# One before the starting LOGSEQ
LOGFILE=$LOGDIR/$MASTERLOG		# Gotta start somewhere

function newlog() {
    if [ "$1" = "$MASTERLOG" ]; then	# Verbatim
	LOGFILE="$1"
    else			# Track ordinality of this build
	LOGFILE="`printf '%02d' $LOGSEQ`_$1"
	let LOGSEQ++
    fi
    LOGFILE="$LOGDIR/$LOGFILE"
}

function log() {
	TS=`date +'%H:%M:%S'`
	echo -e "$TS ${TARGET_ARCH}: $*" | tee -a "$LOGFILE"
}

declare -a WARNINGS
function warning() {
	MSG=`log "$*"`		# Capture stdout which has TS
	WARNINGS+=("$MSG")
}

declare -a ERRORS
function error() {
	MSG=`log "$*"`		# Capture stdout which has TS
	ERRORS+=("$MSG")
}

function die() {
	MSG=`log "$*"`		# Capture stdout which has TS
	echo "$MSG" >&2
	exit 1
}

function dump_warnings_errors() {
	# With set -u, un-altered arrays throw an unbound error on reference.
	set +u

	log "WARNINGS:"
	for (( I=0; I < ${#WARNINGS[@]}; I++ )); do echo "${WARNINGS[$I]}"; done
	
	log "ERRORS:"
	for (( I=0; I < ${#ERRORS[@]}; I++ )); do echo "${ERRORS[$I]}"; done

	[ ${#ERRORS[@]} -eq 0 ]
	RET=$?

	set -u

	return $RET
}

###########################################################################
# Must be called immediately after a command or pipeline of interest.
# Warnings are done manually for now and indicate something odd that
# doesn't seem to prevent success.

function harvest_pipeline_errors() {
    let SUM=`sed 's/ /+/g' <<< "${PIPESTATUS[@]}"`	# first
    [ $# -gt 0 ] && MSG="$*" || MSG="a"
    [ $SUM -ne 0 ] && ERRORS+=("${TARGET_ARCH}: $SUM error(s) in $MSG pipeline of $GITPATH")
    return $SUM
}

###########################################################################
# Check if running in docker or a chroot.  Counting entries in /proc
# is dodgy as it depends on NOT bind mounting /proc before the chroot,
# typically a good idea.  https://stackoverflow.com/questions/23513045
# is more robust.  Of course this depends on grep being in the target
# environment.  The container always has it, the chroot, maybe not.
# This breaks down for exec -it bash.   Okay, go back.

function inContainer() {
	TMP=`grep 2>&1`
	[[ "$TMP" =~ '.*not found$' ]] && return 1 # no grep == not container
	[ ! -d /proc ] && return 1	# again, dodgy
	[ `ls /proc | wc -l` -gt 0 ]
	return $?
}

###########################################################################

function suppressed() {
	if inContainer; then
		REASON=AMD
		$SUPPRESSAMD
	else
		REASON=ARM
		$SUPPRESSARM
	fi
	RET=$?
	[ $RET -eq 0 ] && log "$* ($REASON) is suppressed"
	return $RET
}

###########################################################################
# Clarity.  Not every repo branch follows strict Debian conventions so
# certain failures aren't fatal.

function get_build_prerequisites() {
    [ ! -e debian/rules ] && warning "`basename $GITPATH` missing debian/rules" && return 0
    dpkg-checkbuilddeps &>/dev/null || (echo "y" | mk-build-deps -i -r)
    harvest_pipeline_errors "get_build_prereq"
    return $?
}

###########################################################################
# Call with a github repository reference and an "exit" branch, example:
# get_update_path tm-librarian master
# will be prepended with GHDEFAULT, or supply a "full git path"
# get_update_path https://github.com/SomeOtherOrg/SomeOtherRepo (hold .git)
# Build occurs from wherever the repo is sitting (--git-ignore-new = True).
# Position the repo appropriately ($2).
# Sets globals:
# $GITPATH	absolute path to code, will be working dir on success
# $GITRBRANCHES	The remote branches in the repo
# $GITBUILDIT	Boolean
# Returns:	0 (true) if a new/updated repo is downloaded and should be built
#		  If passed in, FORCEBUILD will override
#		1 (false) if no followon build is needed

readonly GHDEFAULT=https://github.com/FabricAttachedMemory

GITPATH="Main program"	# Set scope
GITRBRANCHES="Larry Curly Moe"
$FORCEBUILD && GITBUILDIT=yes || GITBUILDIT=

function get_update_path() {
    local REPO=$1	# a simple name like "nvml", or full URI https...git
    local GITDEBIANPATH=$2

    GITPATH="$ALLGITS/$REPO"

    echo '---------------------------------------------------------------------'
    REPOBASE=`basename "$REPO"`	# In case they passed a full URI
    newlog $REPOBASE.log
    log "get_update_path $REPO"

    # Only do git clone/pull work in the (original) container so that trailing
    # chroots use the same source, presented via bind mounts.
    if inContainer; then
	if [ ! -d "$GITPATH" ]; then	# First time
	    cd $ALLGITS
	    [ "$REPOBASE" == "$REPO" ] && REPO="${GHDEFAULT}/${REPO}"
	    log Cloning $REPO
	    git clone ${REPO}.git 
	    [ $? -ne 0 ] && error "git clone $REPO failed" && return 1
	    GITBUILDIT=yes
	fi
    fi

    # Both container and chroots need this.
    ! cd $GITPATH && error "cd \"$GITPATH\" failed" && return 1
    GITRBRANCHES=`git branch -r | grep -v HEAD`
    [[ ! "$GITRBRANCHES" =~ "$GITDEBIANPATH" ]] && \
	error "$GITDEBIANPATH not in $REPO" && return 1

    # Locally instantiate all pertinent remote branches.
    for B in debian master upstream; do
	if [[ "$GITRBRANCHES" =~ "$B" ]]; then
	    log "Probing for branch $B"
	    git checkout $B -- >&-
	    [ $? -ne 0 ] && error "git checkout $B failed" && return 1
	    # It might be a re-run.  Clean it up, then check for updates
	    git clean -dff >&-
	    ANS=`git pull 2>&1`
	    [[ "$ANS" =~ "Updating" ]] && GITBUILDIT=yes # yes, any of them
	fi
    done

    # Exit condition
    git checkout $GITDEBIANPATH -- >&- && return 0
    error "Final git checkout $GITDEBIANPATH failed"
    return 1
}

###########################################################################
# Assumes the desired $GITPATH, branch, and $LOGFILE have been preselected.
# --git-export-dir is where the source is copied, one level down, in a
# directory named by repo and changelog version.  The final xxxx.deb files
# go one directory above that copied source, i.e., directly into $GBPOUT.

function build_via_gbp() {
    suppressed "GPB" && return 0
    # This optimization is a holdover from original author and may
    # not actually be useful.
    [ -z "$GITBUILDIT" ] && log "GITBUILDIT is false" && return 1
    log "gbp start at `date`"
    cd $GITPATH || return 1
    get_build_prerequisites	# not for kernel
    GBPARGS="-j$CORES --git-export-dir=$GBPOUT $*"
    log "$GITPATH args: $GBPARGS"
    eval "gbp buildpackage $GBPARGS" 2>&1 | tee -a $LOGFILE
    harvest_pipeline_errors "build_via_gbp"
    RET=$?
    find $GBPOUT -name '*.deb' 2>&- | while read D; do
    	log $D
	mv $D $DEBS
    done
    log "gbp finished"
    return $RET
}

###########################################################################
# Assumes LOGFILE and GITPATH are set, done by get_update_path.

function build_kernel() {
    suppressed "Kernel build" && return 0
    $SUPPRESSKERNEL && log "Kernel explicitly suppressed" && return 0
    cd $GITPATH
    git checkout mdc/linux-4.14.y || die "Cannot switch to kernel LTS branch"
    /bin/pwd
    git status

    log "KERNEL BUILD @ `date`"
    if inContainer; then
        cp config.amd64-fame .config
    else
        cp config.arm64-mft .config
    	# Already set in amd, need it for arm January 2018
    	scripts/config --set-str LOCALVERSION "-l4fame"
    fi

    # Suppress debug kernel - save a few minutes and 500M of space
    # https://superuser.com/questions/925079/compile-linux-kernel-deb-pkg-target-without-generating-dbg-package
    scripts/config --disable DEBUG_INFO &>>$LOGFILE

    # See scripts/link-vmlinux.  Reset the final numeric suffix counter,
    # the "NN" in linux-image-4.14.0-l4fame+_4.14.0-l4fame+-NN_amd64.deb.
    rm -f .version	# restarts at 1

    git add . 
    git commit -a -s -m "Removing -dirty"
    log "Now at `/bin/pwd` ready to make deb-pkg"
    make -j$CORES deb-pkg 2>&1 | tee -a $LOGFILE
    harvest_pipeline_errors "build_kernel"
    RET=$?

    # Artifacts end up one above $GITPATH.  Possibly sign the linux*.changes,
    # then ignore it.
    [ "$GPGID" ] && ( echo "n" | debsign -k"$GPGID" $ALLGITS/linux*.changes )

    mv -f $ALLGITS/linux*.deb $DEBS

    log "kernel finished, $RET error(s)"
    return $RET
}

###########################################################################
# Possibly create an arm chroot, fix it up, and run this script inside  it.
# The sentinel is the existence of the directory autocreated by the 
# qemu-debootstrap command; don't manually create the directory first.

function maybe_build_arm() {
    ! inContainer && return 0	# Stop the recursion
    $SUPPRESSARM && log "ARM build is suppressed" && return 0
    TARGET_ARCH=ARM		# Future actions on behalf of this

    log apt-get install debootstrap qemu-user-static
    apt-get install -y debootstrap qemu-user-static &>> $LOGFILE
    [ ! -d $CHROOT ] && qemu-debootstrap \
    	--arch=arm64 $RELEASE $CHROOT http://deb.debian.org/debian/

    mkdir -p $CHROOT$ALLGITS		# Root of the chroot
    mkdir -p $CHROOT$DEBS		# Root of the chroot

    # Bind mounts allow access from inside the chroot
    mount --bind $ALLGITS $CHROOT$ALLGITS	# ie, the git checkout area
    mkdir -p $DEBS/arm64
    mount --bind $DEBS/arm64 $CHROOT$DEBS	# ARM debs now exposed

    [ -f $KEYFILE ] && cp $KEYFILE $CHROOT

    BUILDER="/$(basename $0)"	# Here in the container
    log Copying $BUILDER to $CHROOT for chroot
    cp $BUILDER $CHROOT
    chroot $CHROOT $BUILDER
    return $?
}

###########################################################################
# Only one branch with source: what a concept.  FIXME: add detection
# instead of this list.  Scan debian/gbp.conf for upstream-branch and
# debian-branch.  If upstream-branch == upstream && there is no master
# and there is a debian branch, do this merging.

function merge_debian_upstream_into_master() {
    REPO=$1
    [[ "$GITRBRANCHES" =~ master ]] && \
	error "Remote master exists in $REPO" && return 1
    for B in debian upstream; do
    	[[ ! "$GITRBRANCHES" =~ "$B" ]] && \
	    error "Remote $B does NOT exist in $REPO" && return 1
    done

    # Always start with no master.  "git clean" gets rid of artifacts
    # from a previous run that could interfere with "checkout debian".
    if git branch | grep -q master; then
	log "Remove local master branch"
	git checkout master --
	git clean -dff
	git checkout debian --
	git branch -D master || die "Couldn't delete master branch"
    fi
    git status | grep -q 'On branch debian' || die "Not on debian"
    git checkout --orphan master || die "debian-orphan failed for $REPO"
    MERGED=`git merge --strategy-option=theirs upstream 2>&1`
    [ $? -ne 0 ] && error "git merge upstream failed\n$MERGED" && return 1
    ls -CF
    return 0
}

###########################################################################
# Build them all, hardcoding the idiosyncracies for now.

function rock_and_roll() {
    # Pure source in upstream; only packaging stuff in debian.  Merge
    # them into a local, no-remote "master" and build.
    for REPO in tm-librarian; do
	get_update_path $REPO debian || return 1
	merge_debian_upstream_into_master $REPO || return 1
	build_via_gbp || return 1
    done

    # Source in both debian and upstream; any master is HPE/MFT specfic.
    # Build from debian.  FIXME: convert these to the "one-copy" model above.
    for REPO in libfam-atomic nvml tm-hello-world tm-libfuse; do
	get_update_path $REPO debian || return 1
	build_via_gbp || return 1
    done

    # Only a master branch and no upstream; master does double duty.
    # l4fame-manager and l4fame-node are metapackages without real source.
    # tm-manifesting should be converted to the one-copy model.
    for REPO in l4fame-manager l4fame-node tm-manifesting; do
	get_update_path $REPO master || return 1
	build_via_gbp || return 1
    done

    # The kernel has its own deb build mechanism
    get_update_path linux-l4fame mdc/linux-4.14.y || return 1
    build_kernel
    return $?
}

############################################################################
# MAIN
# Set globals and accommodate docker runtime arguments.

readonly ARMDIR=/arm
readonly RELEASE=stretch
readonly CHROOT=$ARMDIR/$RELEASE
GPGID=
inContainer && TARGET_ARCH=AMD || TARGET_ARCH=ARM

# "docker run ... -v ...". They are the same from both the container and 
# the chroot.

readonly KEYFILE=/keyfile.key	# optional

rm -rf $LOGDIR || die "Cannot rm -rf $LOGDIR"
mkdir -p $LOGDIR || die "Cannot mkdir $LOGDIR"
newlog $MASTERLOG	# Generic main loop; re-set for each package

echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
ELAPSED=`date +%s`
log "Started at `date`"
log "$*"

# "docker run ... -e CORES=N" or SUPPRESSARM=true
CORES=${CORES:-}
[ "$CORES" ] || let CORES=(`nproc`+1)/2

log "`env | sort`"

# Final setup tasks

if inContainer; then	 # Create the directories used in "docker run -v"
    log In container
    git config --global user.email "example@example.com"   # for commit -s
    git config --global user.name "l4fame-build-container"
    mkdir -p $ALLGITS		# Root of the container
    mkdir -p $DEBS		# Root of the container
else
    log NOT in container
fi 

export DEBIAN_FRONTEND=noninteractive	# Should be in Dockerfile

apt-get update && apt-get upgrade -y
apt-get install -y git-buildpackage
apt-get install -y libssl-dev bc kmod cpio pkg-config build-essential

#--------------------------------------------------------------------------
# Change into build directory and go.  Just keep the debians, no
# *.[build|buildinfo|changes|dsc|orig.tar.gz|.

cd $ALLGITS
rock_and_roll
RARRET=$?

#--------------------------------------------------------------------------

let ELAPSED=(`date +%s`-ELAPSED)/60
newlog $MASTERLOG
log "Finished at `date` ($ELAPSED minutes)"

dump_warnings_errors
[ $? -ne 0 -o $RARRET -ne 0 ] && die "Error(s) occurred"

# But wait there's more!  Let all AMD stuff run from here on out.
# The next routine should get into a chroot very quickly.
maybe_build_arm

exit 0
