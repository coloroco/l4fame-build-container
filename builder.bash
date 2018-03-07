#!/usr/bin/env bash

# This gets copied into a container image and run.  Multiple repos are
# pulled from Github and Debian x86_64 packages created from them.  The
# resulting .deb files are deposited in the "debs" volume from the
# "docker run" command.  Log files for each package build can also be
# found there.  Packages are always downloaded but may not be built
# per these variables.  "false" and "true" are the executables.

SUPPRESSAMD=false			# Mostly for debugging, 45 minutes
SUPPRESSARM=${suppressarm:-false}	# FIXME: in chroot; 2 hours

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

###########################################################################
# Must be called immediately after a command or pipeline of interest.
# Warnings are done manually for now and indicate something odd that
# doesn't seem to prevent success.

function collect_errors() {
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
# Sets the configuration file for gbp.  Note that "debian/rules" is an
# executeable file under fakeroot, with a shebang line of "#!/usr/bin/make -f"
# Insert a postbuild command into the middle of the gbp configuration file
# This indicates to the arm64 chroot which repositories need to be built.
# ignore-new does two things:
# 1. builds even if there are uncommitted changes
# 2. builds EVEN IF THE CURRENT BRANCH IS NOT THE REQUESTED BRANCH

GBPOUT=/gbp-build-area/

function set_gbp_config() {
    P=`/bin/pwd`
    TARGET="../`basename $P`-update"
    [ inContainer ] && CMD=touch || CMD=rm
    cat <<EOGBP > $HOME/.gbp.conf
[DEFAULT]
cleaner = fakeroot debian/rules clean
ignore-new = True
upstream-tree = BRANCH

[buildpackage]
export-dir = $GBPOUT
postbuild = "$CMD $FNAME"

[git-import-orig]
dch = False
EOGBP
}

###########################################################################
# Should only be run in the container?
# Sets the configuration file for debuild.
# Also checks for a signing key to build packages with.

function set_debuild_config() {
    # Check for signing key
    if [ -f $KEYFILE ]; then
        # Remove old keys, import new one, get the key uid
        rm -r $HOME/.gnupg
        gpg --import $KEYFILE
        GPGID=$(gpg -K | grep uid | cut -d] -f2)
        echo "DEBUILD_DPKG_BUILDPACKAGE_OPTS=\"-k'$GPGID' -b -i -j$CORES\"" > $HOME/.devscripts
    else
        echo "DEBUILD_DPKG_BUILDPACKAGE_OPTS=\"-us -uc -b -i -j$CORES\"" > $HOME/.devscripts
    fi
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
# Call with a github repository reference, example:
# get_update_path tm-librarian master
# will be prepended with GHDEFAULT, or supply a "full git path"
# get_update_path https://github.com/SomeOtherOrg/SomeOtherRepo (hold .git)
# Sets globals:
# $GITPATH	absolute path to code, will be working dir on success
# Returns:	0 (true) if a new/updated repo is downloaded and should be built
#		1 (false) if no followon build is needed

readonly GHDEFAULT=https://github.com/FabricAttachedMemory

GITPATH="Main program"	# Set scope

function get_update_path() {
    REPO=$1
    DESIRED=$2
    echo '-----------------------------------------------------------------'
    log "get_update_path $REPO at `date`"

    REPOBASE=`basename "$REPO"`
    newlog $LOGDIR/$REPOBASE.log
    BUILDIT=

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
	[ ! -d "$GITPATH" ] && error "Missing $GITPATH" && return 1
	cd $GITPATH
        RBRANCHES=`git branch -r | grep -v HEAD`
	[[ ! "$RBRANCHES" =~ "$DESIRED" ]] && \
		error "$DESIRED not in $REPO" && return 1
	log Checking branch $DESIRED for updates
        git checkout $BRANCH -- &>/dev/null
	[ $? -ne 0 ] && error "git checkout $BRANCH failed" && return 1
        ANS=`git pull 2>&1`
	[ $? -ne 0 ] && log "git pull on $DESIRED failed:\n$ANS" && return 1
        [[ "$ANS" =~ "Updating" ]] && BUILDIT=yes
    else
    	# In chroot: check if container path above left a sentinel.
    	[ -f $(basename "$GITPATH/$REPOBASE-update") ] && BUILDIT=yes
    fi
    [ "$BUILDIT" ] || return 1
    cd $GITPATH
    [ ! -e debian/rules ] && error "Missing 'debian/rules'" && return 1
    dpkg-checkbuilddeps &>/dev/null || (echo "y" | mk-build-deps -i -r)
    collect_errors
    return $?
}

###########################################################################
# Depends on a correct $GITPATH, branch, and $LOGFILE being preselected.

function build_via_gbp() {
    suppressed "GPB" && return 0
    log "gbp start at `date`"
    GBPARGS="$*"
    cd $GITPATH
    log "$GITPATH args: $GBPARGS"
    eval "gbp buildpackage $GBPARGS" 2>&1 | tee -a $LOGFILE
    collect_errors
    log "gbp finished at `date`"
}

###########################################################################
# Assumes LOGFILE is set

function build_kernel() {
    suppressed "Kernel build" && return 0
    cd $GITPATH
    git checkout mdc/linux-4.14.y || exit 99
    /bin/pwd
    git status

    log "KERNEL BUILD @ `date`"
    if inContainer; then
        cp config.amd64-fame .config
        touch ../$(basename $(pwd))-update
    else
        cp config.arm64-mft .config
    	# Already set in amd, need it for arm January 2018
    	scripts/config --set-str LOCALVERSION "-l4fame"
        rm ../$(basename $(pwd))-update
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
    collect_errors

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
newlog $MASTERLOG		# Generic; re-set for each package

echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
log "Started at `date`"
log "$*"
log "`env | sort`"

ELAPSED=`date +%s`

# "docker run ... -e cores=N" or suppressarm=false
CORES=${cores:-}
[ "$CORES" ] || CORES=$((( $(nproc) + 1) / 2))

for E in CORES SUPPRESSAMD SUPPRESSARM; do
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

# Change into build directory, set the configuration files, then BUILD!
cd $BUILD
set_gbp_config
set_debuild_config

# Using image debian:latest (vs :stretch) seems to have brought along
# a more pedantic gbp that is less forgiving of branch names.
# gbp will take branches like this:
# 1. Only "master" if it has a "debian" directory
# 2. "master" without a "debian" directory if there's a branch named "debian"
#    with a "debian" directory
# 3. "master", "debian", and "upstream" and I don't know what it does
# For all other permutations start slinging options.

# Package		Branches of concern	"debian" dir/	src in
#						build from/
#						private gbp.conf

# Emulation		debian,master		n/a		debian,master
#						master
#						no
# l4fame-manager	master			master		n/a
#						master
#						no
# l4fame-node		master			master		n/a
#						master
#						no
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
# tm-librarian		debian,master,upstream	debian,master	All three
#						debian
#						YES
# tm-manifesting	master			master		master
#						master
#						no

# Build happens from wherever the repo is sitting (--git-ignore-new = True).
# Position the repo appropriately.

#--------------------------------------------------------------------------
# Build <package.version>.orig.tar.gz from upstream (default)

for REPO in l4fame-manager l4fame-node; do
    get_update_path ${REPO}.git master && build_via_gbp
done

for REPO in tm-hello-world tm-libfuse; do
    get_update_path ${REPO}.git debian && build_via_gbp
done

fix_nvml_rules
get_update_path nvml.git debian && \
    build_via_gbp "--git-prebuild='mv -f /tmp/rules debian/rules'"

#--------------------------------------------------------------------------
# Build <package.version>.orig.tar.gz from master
for REPO in libfam-atomic tm-librarian; do 
    get_update_path ${REPO}.git debian && \
    build_via_gbp --git-upstream-branch=master
done

# Manifesting has a bad date in debian/changelog that chokes a Perl module.
# They got more strict in "debian:lastest".  I hate Debian.  For now...
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=795616
get_update_path tm-manifesting.git master
RET=$?
sed -ie 's/July/Jul/' debian/changelog
[ $RET -eq 0 ] && build_via_gbp --git-upstream-branch=master

#--------------------------------------------------------------------------
# The kernel has its own deb build mechanism so ignore retval on...
get_update_path linux-l4fame.git mdc/linux-4.14.y
build_kernel

#--------------------------------------------------------------------------
# That's all, folks!  Right now it's just the debians, no
# *.[build|buildinfo|changes|dsc|orig.tar.gz|.

cp $GBPOUT/*.deb $DEBS

newlog $MASTERLOG
let ELAPSED=`date +%s`-ELAPSED
log "Finished at `date` ($ELAPSED seconds)"

# With set -u, un-altered arrays throw an XXXXX unbound error on reference.
set +u

log "\nWARNINGS:"
for (( I=0; I < ${#WARNINGS[@]}; I++ )); do log "${WARNINGS[$I]}"; done

log "\nERRORS:"
for (( I=0; I < ${#ERRORS[@]}; I++ )); do log "${ERRORS[$I]}"; done

[ ${#ERRORS[@]} -ne 0 ] && die "Error(s) occurred"

set -u

# But wait there's more!  Let all AMD stuff run from here on out.
# The next routine should get into a chroot very quickly.
SUPPRESSAMD=false
maybe_build_arm

exit 0
