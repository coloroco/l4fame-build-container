#!/usr/bin/env bash

set -u

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
# Check for prerequisite build packages, and install them
# If there is a branch named "debian", we use that for installing prerequisites
# Else, use the first branch that contains a folder labeled debian

function run_update() {
    cd "$GITPATH"
    if [[ "$(git branch -r | grep -v HEAD | cut -d'/' -f2)" =~ "debian" ]]; then
        git checkout debian -- &>/dev/null
        if [ -d "debian" ]; then
            ( dpkg-checkbuilddeps &>/dev/null ) || \
            ( echo "y" | mk-build-deps -i -r )
        fi
    else
        for branch in $(git branch -r | grep -v HEAD | cut -d'/' -f2); do
            git checkout $branch -- &>/dev/null
            if [ -d "debian" ]; then
                ( dpkg-checkbuilddeps &>/dev/null ) || \
                ( echo "y" | mk-build-deps -i -r )
                break
            fi
        done
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
# $DOBUILD	true or false (the executable commands) on whether to build
# $GITPATH	absolute path to checked-out code

GHDEFAULT=https://github.com/FabricAttachedMemory

DOBUILD=	# Set scope
GITPATH=

function get_update_path() {
    DOBUILD=false
    REPO=$1
    BN=`basename "$REPO"`
    BNPREFIX=`basename "$BN" .git`	# strip .git off the end
     [ "$BN" == "$BNPREFIX" ] && \
    	echo "$REPO is not a git reference" >&2 && return 1
    GITPATH=$(/bin/pwd)"/$BNPREFIX"
    [ "$BN" == "$REPO" ] && REPO="${GHDEFAULT}/${REPO}"

    # Only do gitwork in the container.  Bind links will expose it to chroot.
    if inContainer; then
        if [ ! -d "$GITPATH"  ]; then	# First time
            git clone "$REPO"
            DOBUILD=true
	    return 0
	fi

        # Update any branches that need it.
	cd $GITPATH
        for branch in $(git branch -r | grep -v HEAD | cut -d'/' -f2); do
                git checkout $branch -- &>/dev/null
                ANS=$(git pull)
                [[ "$ANS" =~ "Updating" ]] && DOBUILD=true
        done
	return 0
    fi
    
    # In chroot: check if docker marked the repository as needing a rebuild
    if [ -f $(basename $GITPATH"-update") ]; then
            # Update found, build package
            DOBUILD=true
    fi
    return 0
}

###########################################################################

function build_kernel() {
    cd $GITPATH
    git checkout mdc/linux-4.14.y || exit 99
    if inContainer; then
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
    make -j$CORES deb-pkg 2>&1 | tee $BUILD/kernel.log

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
	echo "$E=${$E}"
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

get_update_path l4fame-node.git
( $DOBUILD ) && ( run_update && gbp buildpackage )

get_update_path l4fame-manager.git
( $DOBUILD ) && ( run_update && gbp buildpackage )

get_update_path tm-libfuse.git
( $DOBUILD ) && ( run_update && gbp buildpackage )

get_update_path tm-librarian.git
( $DOBUILD ) && ( run_update && gbp buildpackage )

get_update_path tm-hello-world.git
( $DOBUILD ) && ( run_update && gbp buildpackage )

get_update_path libfam-atomic.git
( $DOBUILD ) && ( run_update && gbp buildpackage --git-upstream-tree=branch )

get_update_path tm-manifesting.git
( $DOBUILD ) && ( run_update && gbp buildpackage --git-upstream-branch=master --git-upstream-tree=branch )

get_update_path Emulation.git
( $DOBUILD ) && ( run_update && gbp buildpackage --git-upstream-branch=master )

exit 0

fix_nvml_rules
get_update_path nvml.git
( $DOBUILD ) && ( run_update && gbp buildpackage --git-prebuild='mv -f /tmp/rules debian/rules' )

# The kernel has its own deb mechanism.
get_update_path linux-l4fame.git
( $DOBUILD ) && build_kernel

# That's all, folks!
cp $GBPOUT/*.deb $DEBS
cp $GBPOUT/*.changes $DEBS

# But wait there's more!
inContainer && maybe_build_arm

echo "Finished at `date`"

exit 0
