#!/usr/bin/env bash

# This gets copied into a container image and run.  Multiple repos are
# pulled from Github and Debian x86_64 packages created from them.  The
# resulting .deb files are deposited in the "debs" volume from the
# "docker run" command.  Log files for each package build can also be
# found there.  Packages are always downloaded but may not be built
# per these variables.  "false" and "true" are the executables.
# docker run ..... -e suppressxxx=true l4fame-build

export FORCEBUILD=${forcebuild:-true}
export SUPPRESSAMD=${suppressamd:-false}	# Mostly for debugging, 45 minutes
export SUPPRESSARM=${suppressarm:-false}	# FIXME: in chroot; 2 hours
export SUPPRESSKERNEL=${suppresskernel:-false}	# Most of the time

set -u

###########################################################################
# Convenience routines.

LOGFILE=
declare -a ERRORS WARNINGS

function newlog() {
	LOGFILE="$1"
	mkdir -p `dirname "$LOGFILE"`
}

function log() {
	echo -e "$*" | tee -a "$LOGFILE"
}

function warning() {
	MSG="$*"
	log $MSG
	WARNINGS+=($MSG)
}

function error() {
	MSG="$*"
	log $MSG
	ERRORS+=($MSG)
}

function die() {
	log "$*"
	echo "$*" >&2
	exit 1
}

function dump_warnings_errors() {
	# With set -u, un-altered arrays throw an unbound error on reference.
	set +u

	log "\nWARNINGS:"
	for (( I=0; I < ${#WARNINGS[@]}; I++ )); do log "${WARNINGS[$I]}"; done
	
	log "\nERRORS:"
	for (( I=0; I < ${#ERRORS[@]}; I++ )); do log "${ERRORS[$I]}"; done

	[ ${#ERRORS[@]} -ne 0 ] && die "Error(s) occurred"

	set -u
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

function update_name() {
    P=`/bin/pwd`
    TARGET="../`basename $P`-update"
    echo $TARGET
}

###########################################################################
# Builds a new debian/rules file for nvml

function fix_nvml_rules() {
    read -r -d '' rule << "EOF"
#!/usr/bin/make -f
%:
\tdh \$@

override_dh_auto_install:
\tdh_auto_install -- prefix=/usr

override_dh_install:
\tmkdir -p debian/tmp/usr/share/nvml/
\tcp utils/nvml.magic debian/tmp/usr/share/nvml/
\t-mv -f debian/tmp/usr/lib64 debian/tmp/usr/lib
\tdh_install

override_dh_auto_test:
\techo "We do not test this code yet."

override_dh_clean:
\tfind src/ -name 'config.status' -delete
\tfind src/ -name 'config.log' -delete
\tdh_clean
EOF

    echo -e "$rule" > /tmp/rules
    chmod +x /tmp/rules
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
    echo '-----------------------------------------------------------------'
    REPOBASE=`basename "$REPO"`
    newlog $LOGDIR/$REPOBASE.log
    log "get_update_path $REPO at `date`"

    $FORCEBUILD && BUILDIT=yes || BUILDIT=

    GITPATH="$BUILD/$REPO"
    [ "$REPOBASE" == "$REPO" ] && REPO="${GHDEFAULT}/${REPO}"

    # Only do git work in the container.  Bind links will expose it to chroot.
    if inContainer; then
        if [ ! -d "$GITPATH" ]; then	# First time
	    cd $BUILD
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

	# Realize all pertinent branches locally for gbp
	for B in debian master upstream; do git checkout $B -- >&-; done

	# Where's the beef?
	log Checking branch $DESIRED for updates
        git checkout $DESIRED -- &>/dev/null
	[ $? -ne 0 ] && error "git checkout $DESIRED failed" && return 1
        ANS=`git pull 2>&1`
	[ $? -ne 0 ] && log "git pull on $DESIRED failed:\n$ANS" && return 1
        [[ "$ANS" =~ "Updating" ]] && BUILDIT=yes
    else
    	# In chroot: check if container path above left a sentinel.
    	[ -f $(update_name) ] && BUILDIT=yes
    fi
    cd $GITPATH			# exit condition
    [ "$BUILDIT" ] || return 1
    get_build_prerequisites
    return $?
}

###########################################################################
# Assumes the desired $GITPATH, branch, and $LOGFILE have been preselected.

function build_via_gbp() {
    suppressed "GPB" && return 0
    log "gbp start at `date`"
    GBPARGS="-j$CORES --git-export-dir=$GBPOUT $*"
    cd $GITPATH
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
        touch `update_name`
    else
        cp config.arm64-mft .config
    	# Already set in amd, need it for arm January 2018
    	scripts/config --set-str LOCALVERSION "-l4fame"
        rm `update_name`
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
    mv -f $BUILD/linux*.* $GBPOUT	# Keep them with all the others

    # Sign the linux*.changes file if applicable
    [ "$GPGID" ] && ( echo "n" | debsign -k"$GPGID" $GBPOUT/linux*.changes )

    log "kernel finished at `date`"
}

###########################################################################
# Possibly create an arm chroot, fix it up, and run this script inside  it.

function maybe_build_arm() {
    ! inContainer && return 1	# infinite recursion
    suppressed "ARM building" && return 0

    # build an arm64 chroot if none exists.  The sentinel is the existence of
    # the directory autocreated by the qemu-debootstrap command, ie, don't
    # manually create the directory first.

    log apt-get install debootstrap qemu-user-static
    apt-get install -y debootstrap qemu-user-static &>> $LOGFILE
    [ ! -d $CHROOT ] && qemu-debootstrap \
    	--arch=arm64 $RELEASE $CHROOT http://deb.debian.org/debian/

    mkdir -p $CHROOT$BUILD		# Root of the chroot
    mkdir -p $CHROOT$DEBS		# Root of the chroot

    # Bind mounts allow access from inside the chroot
    mount --bind $BUILD $CHROOT$BUILD		# ie, the git checkout area
    mkdir -p $DEBS/arm64
    mount --bind $DEBS/arm64 $CHROOT$DEBS	# ARM debs also visible

    [ -f $KEYFILE ] && cp $KEYFILE $CHROOT

    BUILDER="/$(basename $0)"	# Here in the container
    log Next, cp $BUILDER $CHROOT
    cp $BUILDER $CHROOT
    chroot $CHROOT $BUILDER \
    	'cores=$CORES' 'http_proxy=$http_proxy' 'https_proxy=$https_proxy'
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
# is specified in each repo's debian/gbp.conf.

function rock_and_roll() {

    # Only one branch with source.  What a concept. 
    for REPO in tm-librarian; do
	get_update_path_repo $REPO debian
	git branch -D master >&-
	git checkout --orphan master
	build_via_gbp
    done

    # Only a master branch, and no upstream.   Master does double duty.
    # manager and node are metapackages, without real source.  manifesting
    # should be converted to the one-copy model.
    for REPO in l4fame-manager l4fame-node tm-manifesting; do
	get_update_path $REPO master && build_via_gbp
    done

    # debian and upstream, some with master.  Build from debian but
    # convert these to the "one-copy" model.
    for REPO in libfam-atomic tm-hello-world tm-libfuse; do
	get_update_path $REPO debian && build_via_gbp
    done

    fix_nvml_rules
    get_update_path nvml debian && \
	build_via_gbp "--git-prebuild='mv -f /tmp/rules debian/rules'"

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

readonly BUILD=/build
readonly DEBS=/debs
readonly KEYFILE=/keyfile.key	# optional
readonly LOGDIR=$DEBS/logs
readonly MASTERLOG=$LOGDIR/1st.log

rm -rf $LOGDIR
mkdir -p $LOGDIR

echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
ELAPSED=`date +%s`
newlog $MASTERLOG		# Generic; re-set for each package
log "Started at `date`"
log "$*"
log "`env | sort`"

# "docker run ... -e cores=N" or suppressarm=false
CORES=${cores:-}
[ "$CORES" ] || CORES=$((( $(nproc) + 1) / 2))

for E in CORES FORCEBUILD SUPPRESSAMD SUPPRESSARM; do
	eval VAL=\$$E
	log "$E=$VAL"
done

# Final setup tasks

if inContainer; then	 # Create the directories used in "docker run -v"
    log In container
    git config --global user.email "example@example.com"   # for commit -s
    git config --global user.name "l4fame-build-container"
    mkdir -p $BUILD		# Root of the container
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

cd $BUILD
rock_and_roll
cp $GBPOUT/*.deb $DEBS

#--------------------------------------------------------------------------

let ELAPSED=(`date +%s`-ELAPSED)/60
newlog $MASTERLOG
log "Finished at `date` ($ELAPSED minutes)"

dump_warnings_errors

# But wait there's more!  Let all AMD stuff run from here on out.
# The next routine should get into a chroot very quickly.
maybe_build_arm

exit 0
