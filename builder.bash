#!/usr/bin/env bash

# This gets copied into a container image and run.  Multiple repos are
# pulled from Github and Debian x86_64 packages created from them.  The
# resulting .deb files are deposited in the "debs" volume from the
# "docker run" command.  Log files for each package build can also be
# found there.  Packages are always downloaded but may not be built
# per these variables.  "false" and "true" are the executables.
# docker run ..... -e suppressxxx=true l4fame-build

# SUPPRESSXXX is usually for debugging, skipping things that work and
# saving time to reach broken things faster.  Time is for 90 cores.
# The variables are executed at runtime and resolve to /bin/[true|false]
export SUPPRESSAMD=${SUPPRESSAMD:-false}	# saves 45 minutes
export SUPPRESSARM=${SUPPRESSARM:-false}	# in chroot; saves 1 hour
export SUPPRESSKERNEL=${SUPPRESSKERNEL:-false}	# 5-8 minutes AMD, 45 ARM

# Override optimizations that might skip building.  There aren't many.
export FORCEBUILD=${FORCEBUILD:-true}

set -u

# Global directories

readonly ALLGITS=/allgits		# Where "git clone" goes
readonly DEBS=/debs			# Where finished packages go
readonly GBPOUT=/gbp-build-area		# Where "gbp --git-export-dir" goes

###########################################################################
# Convenience routines.  Can't call them in early execution until their
# "private" globals have been set.

readonly LOGDIR=$DEBS/logs
readonly MASTERLOG=00_mainloop.log
LOGFILE=$LOGDIR/$MASTERLOG
declare -i LOGSEQ=1

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
	inContainer && WHERE=AMD || WHERE=ARM
	echo -e "$TS ${WHERE}: $*" | tee -a "$LOGFILE"
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
    let SUM=`sed 's/ /+/g' <<< "${PIPESTATUS[@]}"`
    [ $SUM -ne 0 ] && ERRORS+=("$SUM error(s) in a pipeline of $GITPATH")
    return $SUM
}

###########################################################################
# Check if we're running in docker or a chroot.  Counting entries in /proc
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
# Sentinel from container (AMD and git work) to chroot (ARM work)

function update_sentinel() {
    P=`/bin/pwd`
    TARGET="../`basename $P`-update"
    echo $TARGET
}

###########################################################################
# Clarity.  Not every package follows strict Debian conventions so
# certain failures aren't fatal.

function get_build_prerequisites() {
    [ ! -e debian/rules ] && warning "`basename $GITPATH` missing debian/rules" && return 0
    dpkg-checkbuilddeps &>/dev/null || (echo "y" | mk-build-deps -i -r)
    harvest_pipeline_errors
    return $?
}


###########################################################################
# Call with a github repository reference, example:
# get_update_path tm-librarian master
# will be prepended with GHDEFAULT, or supply a "full git path"
# get_update_path https://github.com/SomeOtherOrg/SomeOtherRepo (hold .git)
# Sets globals:
# $GITPATH	absolute path to code, will be working dir on success
# Returns:	0 (true) if a new/updated repo is downloaded and should be built
#		  If passed in, FORCEBUILD will override
#		1 (false) if no followon build is needed

readonly GHDEFAULT=https://github.com/FabricAttachedMemory

GITPATH="Main program"	# Set scope

function get_update_path() {
    REPO=$1
    DESIRED=$2
    echo '---------------------------------------------------------------------'
    REPOBASE=`basename "$REPO"`
    newlog $REPOBASE.log
    log "get_update_path $REPO at `date`"

    $FORCEBUILD && BUILDIT=yes || BUILDIT=

    GITPATH="$ALLGITS/$REPO"
    [ "$REPOBASE" == "$REPO" ] && REPO="${GHDEFAULT}/${REPO}"

    # Only do git work in the container.  Bind mounts will expose it to chroot.
    if ! inContainer; then
        cd $GITPATH || die "Cannot cd $GITPATH"
    	[ -f "`update_sentinel`" ] && BUILDIT=yes
	git checkout $DESIRED -- || die "Cannot checkout $DESIRED"
	return $?
    fi

    # In container, aka the AMD pass
    if [ ! -d "$GITPATH" ]; then	# First time
	cd $ALLGITS
	log Cloning $REPO
        git clone ${REPO}.git 
	[ $? -ne 0 ] && error "git clone $REPO failed" && return 1
	BUILDIT=yes
    fi
    [ ! -d "$GITPATH" ] && error "$REPO no path \"$GITPATH\"" && return 1
    cd $GITPATH
    RBRANCHES=`git branch -r | grep -v HEAD`
    [[ ! "$RBRANCHES" =~ "$DESIRED" ]] && \
	error "$DESIRED not in $REPO" && return 1

    # Locally instantiate all pertinent remote branches.
    for B in debian master upstream; do
	if [[ ! "$RBRANCHES" =~ "$B" ]]; then	# NOT for a merged master!
	    log "Probing for branch $B"
	    git checkout $B -- >&-
	    if [ $? -eq 0 ]; then
		# 1. It might be a re-run.  Do some cleanup.
		git clean -dff >&-
		# 2. It might not exist.  It's not an error.
       		ANS=`git pull 2>&1`
       		[[ "$ANS" =~ "Updating" ]] && BUILDIT=yes # yes, any of them
	    else
	    	[ $B == $DESIRED ] && error "checkout $B failed" && return 1
	    fi
	fi
    done

    # Exit condition
    git checkout $DESIRED -- >&-
    [ $? -ne 0 ] && error "Final git checkout $DESIRED failed" && return 1
    cd $GITPATH			# exit condition
    return $?
}

###########################################################################
# Assumes the desired $GITPATH, branch, and $LOGFILE have been preselected.

function build_via_gbp() {
    suppressed "GPB" && return 0
    [ "$BUILDIT" ] || return 1
    log "gbp start at `date`"
    cd $GITPATH
    get_build_prerequisites
    GBPARGS="-j$CORES --git-export-dir=$GBPOUT $*"
    log "$GITPATH args: $GBPARGS"
    eval "gbp buildpackage $GBPARGS" 2>&1 | tee -a $LOGFILE
    harvest_pipeline_errors
    log "gbp finished at `date`"
}

###########################################################################
# Assumes LOGFILE and GITPATH are set, done by get_update_path.

function build_kernel() {
    suppressed "Kernel build" && return 0
    suppresskernel && log "Kernel explicitly suppressed" && return 0
    cd $GITPATH
    git checkout mdc/linux-4.14.y || die "Cannot switch to kernel LTS branch"
    /bin/pwd
    git status

    log "KERNEL BUILD @ `date`"
    if inContainer; then
        cp config.amd64-fame .config
        touch `update_sentinel`
    else
        cp config.arm64-mft .config
    	# Already set in amd, need it for arm January 2018
    	scripts/config --set-str LOCALVERSION "-l4fame"
        rm `update_sentinel`
    fi

    # Suppress debug kernel - save a few minutes and 500M of space
    # https://superuser.com/questions/925079/compile-linux-kernel-deb-pkg-target-without-generating-dbg-package
    scripts/config --disable DEBUG_INFO &>>$LOGFILE

    # See scripts/link-vmlinux.  Reset the final numeric suffix counter,
    # the "NN" in linux-image-4.14.0-l4fame+_4.14.0-l4fame+-NN_amd64.deb.
    rm -f .version	# restarts at 1

    git add . 
    git commit -a -s -m "Removing -dirty"
    log "Now at `/bin/pwd` ready to make"
    make -j$CORES deb-pkg 2>&1 | tee -a $LOGFILE
    harvest_pipeline_errors

    # They end up one above $GITPATH???
    mv -f $ALLGITS/linux*.* $GBPOUT	# Keep them with all the others

    # Sign the linux*.changes file if applicable
    [ "$GPGID" ] && ( echo "n" | debsign -k"$GPGID" $GBPOUT/linux*.changes )

    log "kernel finished at `date`"
}

###########################################################################
# Possibly create an arm chroot, fix it up, and run this script inside  it.

function maybe_build_arm() {
    ! inContainer && log "Unsupported call to maybe_build_arm" && return 1
    $SUPPRESSARM && log "ARM build is suppressed" && return 0

    # build an arm64 chroot if none exists.  The sentinel is the existence of
    # the directory autocreated by the qemu-debootstrap command, ie, don't
    # manually create the directory first.

    log apt-get install debootstrap qemu-user-static
    apt-get install -y debootstrap qemu-user-static &>> $LOGFILE
    [ ! -d $CHROOT ] && qemu-debootstrap \
    	--arch=arm64 $RELEASE $CHROOT http://deb.debian.org/debian/

    mkdir -p $CHROOT$ALLGITS		# Root of the chroot
    mkdir -p $CHROOT$DEBS		# Root of the chroot

    # Bind mounts allow access from inside the chroot
    mount --bind $ALLGITS $CHROOT$ALLGITS	# ie, the git checkout area
    mkdir -p $DEBS/arm64
    mount --bind $DEBS/arm64 $CHROOT$DEBS	# ARM debs also visible

    [ -f $KEYFILE ] && cp $KEYFILE $CHROOT

    BUILDER="/$(basename $0)"	# Here in the container
    log Copying $BUILDER to $CHROOT for chroot
    cp $BUILDER $CHROOT
    chroot $CHROOT $BUILDER
    return $?
}

###########################################################################
# Using image debian:latest (vs :stretch) seems to have brought along
# a more pedantic gbp that is less forgiving of branch names.

# Package		Branches of concern	"debian" dir/	src in
#						build from/
#						private gbp.conf

# Emulation		debian,master		n/a		debian,master
#						master
#						no
# l4fame-manager	master			master		n/a
#						master
#						YES
# l4fame-node		master			master		n/a
#						master
#						YES
# libfam-atomic		debian,master,upstream	debian,master	All three
#						debian
#						YES
# nvml			debian,master,upstream	debian		All three
#						debian
#						YES
# tm-hello-world	debian,master		debian		debian,master
#						debian
#						YES
# tm-libfuse		debian,hp_l4tm,upstream	debian,hp_l4tm	All three
#						debian
#						YES
# tm-librarian		debian,upstream		debian		upstream
#						merged master
#						YES
# tm-manifesting	master			master		master
#						master
#						YES

# Build happens from wherever the repo is sitting (--git-ignore-new = True).
# Position the repo appropriately.  <package.version>.orig.tar.gz "source"
# is specified in each repo's debian/gbp.conf, as are the upstream-branch
# and debian-branch.

function rock_and_roll() {
    # Only one branch with source: what a concept.  FIXME: add detection
    # instead of this list.  Scan debian/gbp.conf for upstream-branch and
    # debian-branch.  If upstream-branch == upstream && there is no master
    # and there is a debian branch, do this merging.
    for REPO in tm-librarian; do
	get_update_path $REPO debian || die "Couldn't git $REPO"
	if git branch | grep -q master; then	# Get rid of it and start fresh
	    log "Reset master branch"
	    git checkout master --
	    git clean -dff
	    git checkout debian --
	    git branch -D master || die "Couldn't delete master branch"
	fi
	git status | grep -q 'On branch debian' || die "Not on debian"
	git checkout --orphan master || die "debian-orphan failed for $REPO"
	MERGED=`git merge --strategy-option=theirs upstream 2>&1`
	[ $? -ne 0 ] && die "git merge upstream failed\n$MERGED"
	ls -CF
	build_via_gbp || return 1
    done

    # debian and upstream, some with master that might be HPE/MFT specfic.
    # Build from debian.  FIXME convert these to the "one-copy" model above.
    for REPO in libfam-atomic nvml tm-hello-world tm-libfuse; do
	get_update_path $REPO debian && build_via_gbp
	[ $? -ne 0 ] && error "get/build failed for $REPO" && return 1
    done

    # Only a master branch and no upstream; master does double duty.
    # manager and node are metapackages, without real source.  manifesting
    # should be converted to the one-copy model.  The others could fit
    # into a detection scheme which skips the merge to master.
    for REPO in l4fame-manager l4fame-node tm-manifesting; do
	get_update_path $REPO master && build_via_gbp
	[ $? -ne 0 ] && error "get/build failed for $REPO" && return 1
    done

    # The kernel has its own deb build mechanism
    get_update_path linux-l4fame mdc/linux-4.14.y && build_kernel
}

############################################################################
# MAIN
# Set globals and accommodate docker runtime arguments.

readonly ARMDIR=/arm
readonly RELEASE=stretch
readonly CHROOT=$ARMDIR/$RELEASE
GPGID=

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
cp $GBPOUT/*.deb $DEBS

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
