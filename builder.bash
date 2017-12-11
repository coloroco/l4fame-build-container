#!/usr/bin/env bash

set -u

###########################################################################

function die() {
	echo "$*" >&2
	exit 1
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

###########################################################################
# Sets the configuration file for gbp

GBPOUT=/gbp-build-area/

function set_gbp_config () {
    cat <<EOF > $HOME/.gbp.conf
[DEFAULT]
cleaner = fakeroot debian/rules clean
ignore-new = True

[buildpackage]
export-dir = $GBPOUT

EOF

    # Insert a postbuild command into the middle of the gbp configuration file
    # This indicates to the arm64 chroot which repositories need to be built
    if inContainer; then	# mark repositories to be built
        echo "postbuild=touch ../\$(basename \$(pwd))-update" >> $HOME/.gbp.conf
    else
        # In chroot, mark repositories as already built
        echo "postbuild=rm ../\$(basename \$(pwd))-update" >> $HOME/.gbp.conf
    fi
    cat <<EOF >> $HOME/.gbp.conf
[git-import-orig]
dch = False
EOF
}

###########################################################################
# Should only be run in the container?
# Sets the configuration file for debuild.
# Also checks for a signing key to build packages with

function set_debuild_config () {
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
# If there is a branch named "debian", use that;
# Else use the first branch that contains a folder labeled debian;
# Else die.
# Finally, check for prerequisite build packages, and install them

function get_build_prerequisites() {
    echo get_build_prerequisites $GITPATH
    cd "$GITPATH"
    if [[ "$(git branch -r | grep -v HEAD | cut -d'/' -f2)" =~ "debian" ]]; then
        git checkout debian -- &>/dev/null
        [ -d "debian" ] || die "'debian' branch has no 'debian' directory"
	BRANCH=debian
    else
        for BRANCH in $(git branch -r | grep -v HEAD | cut -d'/' -f2); do
            git checkout $BRANCH -- &>/dev/null
            [ -d "debian" ] && break
	    BRANCH=	# sentinel for exhausting the loop
        done
	[ "$BRANCH" ] || die "No branch has a 'debian' directory"
    fi
    echo get_build_prerequisites found "debian" directory in $BRANCH
    if [ -e debian/rules ]; then
    	dpkg-checkbuilddeps >/dev/null 2>&1 || (echo "y" | mk-build-deps -i -r)
    else
    	echo "Branch $BRANCH has no 'debian/rules'"
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
# Call with a github repository URL, example:
# get_update_path tm-librarian.git
# will be prepended with GHDEFAULT, or supply a "full git path"
# get_update_path https://github.com/SomeOtherOrg/SomeOtherRepo.git
# Sets globals:
# $GITPATH	absolute path to code, will be working dir on success

GHDEFAULT=https://github.com/FabricAttachedMemory

GITPATH=/nada	# Set scope

function get_update_path() {
    REPO=$1
    RUN_UPDATE=
    echo '-----------------------------------------------------------------'
    echo get_update_path $REPO

    BN=`basename "$REPO"`
    BNPREFIX=`basename "$BN" .git`	# strip .git off the end
    [ "$BN" == "$BNPREFIX" ] && \
    	echo "$REPO is not a git reference" >&2 && return 1
    GITPATH="$BUILD/$BNPREFIX"
    [ "$BN" == "$REPO" ] && REPO="${GHDEFAULT}/${REPO}"

    # Only do git work in the container.  Bind links will expose it to chroot.
    if inContainer; then
        if [ ! -d "$GITPATH"  ]; then	# First time
	    cd $BUILD
            git clone "$REPO" || die "git clone $REPO failed"
	    [ -d "$GITPATH" ] || die "git clone $REPO worked but no $GITPATH"
	else			# Update any branches that need it.
	    cd $GITPATH
            for branch in $(git branch -r | grep -v HEAD | cut -d'/' -f2); do
                git checkout $branch -- &>/dev/null
                ANS=$(git pull)
                [[ "$ANS" =~ "Updating" ]] && RUN_UPDATE=yes && break
            done
	fi
    else
    	# In chroot: check if container path above left a sentinel.
    	[ -f $(basename "$GITPATH-update") ] && RUN_UPDATE=yes
    fi
    get_build_prerequisites
    return $?
}

###########################################################################
# Depends on a correct $GITPATH

function build_via_gbp() {
    shift
    GBPARGS="$*"
}

###########################################################################

function build_kernel() {
    echo "cd to $GITPATH"
    cd $GITPATH
    git checkout mdc/linux-4.14.y || exit 99
    /bin/pwd
    git status

    if inContainer; then
	echo KERNEL BUILD IN CONTAINER
        cp config.amd64-l4fame .config
        touch ../$(basename $(pwd))-update

	# November 2017: stretch has gcc 6.3.0 and it picks up an error in
	# fam-atomic and I need this for Discover and FAME.  Greg will
	# probably fix it in time, but until then:
	sed -ie 's/CONFIG_FAM_ATOMIC=m/CONFIG_FAM_ATOMIC=n/' .config

    else
        cp config.arm64-mft .config
        rm ../$(basename $(pwd))-update
    fi
    git add . 
    git commit -a -s -m "Removing -dirty"
    echo "Now at `/bin/pwd` ready to make"
    make -j$CORES deb-pkg 2>&1 | tee $BUILD/kernel.log

    # They end up one above $GITPATH???
    mv -f $BUILD/linux*.* $GBPOUT	# Keep them with all the others

    # Sign the linux*.changes file if applicable
    [ "$GPGID" ] && ( echo "n" | debsign -k"$GPGID" $GBPOUT/linux*.changes )
}

###########################################################################
# Possibly create an arm chroot, fix it up, and run this script inside  it.

function maybe_build_arm() {
    $SUPPRESSARM && return 1

    # build an arm64 chroot if none exists.  The sentinel is the existence of
    # the directory autocreated by the qemu-debootstrap command, ie, don't
    # manually create the directory first.

    apt-get install -y debootstrap qemu-user-static
    [ ! -d $CHROOT ] && qemu-debootstrap \
    	--arch=arm64 $RELEASE $CHROOT http://deb.debian.org/debian/

    mkdir $CHROOT$BUILD		# Root of the chroot
    mkdir $CHROOT$DEBS		# Root of the chroot

    # Bind mounts allow access from inside the chroot
    mount --bind $BUILD $CHROOT$BUILD		# ie, the git checkout area
    mkdir -p $DEBS/arm64
    mount --bind $DEBS/arm64 $CHROOT$DEBS	# ARM debs also visible

    [ -f $KEYFILE ] && cp $KEYFILE $CHROOT

    cp "$0" $CHROOT
    chroot $CHROOT "/$(basename $0)" 'cores=$CORES' 'http_proxy=$http_proxy' 'https_proxy=$https_proxy'
    return $?
}

###########################################################################
# MAIN
# Set globals and accommodate docker runtime arguments.


echo '!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!'
date

ARMDIR=/arm
RELEASE=stretch
CHROOT=$ARMDIR/$RELEASE
GPGID=

# "docker run ... -v ...". They are the same from both the container and 
# the chroot.

BUILD=/build
DEBS=/deb
KEYFILE=/keyfile.key		# optional

# "docker run ... -e cores=N" or suppressarm=false
CORES=${cores:-}
[ "$CORES" ] || CORES=$((( $(nproc) + 1) / 2))
SUPPRESSARM=${suppressarm:-true}	# true or false

for E in CORES SUPPRESSARM; do
	eval VAL=\$$E
	echo "$E=$VAL"
done

# Other setup tasks

git config --global user.email "example@example.com"	# for commit -s
git config --global user.name "l4fame-build-container"

if inContainer; then	 # Create the directories used in "docker run -v"
    echo In container
    mkdir -p $BUILD		# Root of the container
    mkdir -p $DEBS		# Root of the container
else
    echo NOT in container
    # apt-get install -y linux-image-arm64	Austin's first try?
fi 

export DEBIAN_FRONTEND=noninteractive	# Should be in Dockerfile

apt-get update && apt-get upgrade -y
apt-get install -y git-buildpackage
apt-get install -y libssl-dev bc kmod cpio pkg-config build-essential

# Change into build directory, set the configuration files, then BUILD!
cd $BUILD
set_gbp_config
set_debuild_config

get_update_path l4fame-node.git && gbp buildpackage

get_update_path l4fame-manager.git && gbp buildpackage

get_update_path tm-libfuse.git && gbp buildpackage

get_update_path tm-librarian.git && gbp buildpackage

get_update_path tm-hello-world.git && gbp buildpackage

get_update_path libfam-atomic.git && \
    gbp buildpackage --git-upstream-tree=branch

get_update_path tm-manifesting.git && \
    gbp buildpackage --git-upstream-branch=master --git-upstream-tree=branch

get_update_path Emulation.git && \
    gbp buildpackage --git-upstream-branch=master

fix_nvml_rules
get_update_path nvml.git && \
    gbp buildpackage --git-prebuild='mv -f /tmp/rules debian/rules'

# The kernel has its own deb build mechanism.
get_update_path linux-l4fame.git && build_kernel

# That's all, folks!
cp $GBPOUT/*.deb $DEBS
cp $GBPOUT/*.changes $DEBS

# But wait there's more!
inContainer && maybe_build_arm

echo "Finished at `date`"

exit 0
