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

function set_gbp_config () {
    cat <<EOF > $HOME/.gbp.conf
[DEFAULT]
cleaner = fakeroot debian/rules clean
ignore-new = True

[buildpackage]
export-dir = /gbp-build-area/

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
    if [ -f "/keyfile.key" ]; then
        # Remove old keys, import keyfile.key, get the key uid
        rm -r $HOME/.gnupg
        gpg --import /keyfile.key
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
# $GITPATH	absolute path to checked-out code
# $BUILD	true or false (the executable commands) on whether to build

GHDEFAULT=https://github.com/FabricAttachedMemory

BUILD=		# Set scope
GITPATH=

function get_update_path() {
    BUILD=false
    REPO=$1
    BN=`basename "$REPO"`
    BNPREFIX=`basename "$BN" .git`	# strip .git off the end
    [ "$BN" == "$BNPREFIX"] && \
    	echo "$REPO is not a git reference" >&2 && return 1
    GITPATH=$(/bin/pwd)"/$BNPREFIX"
    [ "$BN" == "$REPO" ] && REPO="${GHDEFAULT}/${REPO}"

    # Check if we're running in docker or a chroot
    if inContainer; then
        # Check if the repository needs to be cloned, then clone
        if [ ! -d "$GITPATH"  ]; then
            git clone "$REPO"
            BUILD=true
        else
            # Check if any branch in the repository needs to be updated, then update
            for branch in $(cd $GITPATH && git branch -r | grep -v HEAD | cut -d'/' -f2); do
                (cd $GITPATH && git checkout $branch -- &>/dev/null)
                ANS=$(cd $GITPATH && git pull)
                if [[ "$ANS" =~ "Updating" ]]; then
                    BUILD=true
                fi
            done
        fi
    else
        # Check if docker marked the repository as needing a rebuild
        if [ -f $(basename $GITPATH"-update") ]; then
            # Update found, build package
            BUILD=true
        fi
    fi
    return 0
}

###########################################################################
# Set .config file for amd64 and arm64, then remove the dirty kernel build
# messages

function set_kernel_config() {
    git config --global user.email "example@example.com"
    git config --global user.name "l4fame-build-container"
    if inContainer; then
        cp config.l4fame .config
    else
        yes '' | make oldconfig
    fi
    git add . 
    git commit -a -s -m "Removing -dirty"
}

###########################################################################
# MAIN

if inContainer; then
	echo In container
else
	echo NOT in container
fi

export DEBIAN_FRONTEND=noninteractive	# Should be in Dockerfile

apt-get update && apt-get upgrade -y
apt-get install -y git-buildpackage
apt-get install -y libssl-dev bc kmod cpio pkg-config build-essential

if inContainer; then
    apt-get install -y debootstrap qemu qemu-user-static
else
    apt-get install -y linux-image-arm64
fi

# If user sets "-e cores=number_of_cores" use that many cores when compiling
# Otherwise set $CORES to half the cpu cores.
CORES=${cores:-}
[ "$CORES" ] || CORES=$((( $(nproc) + 1) / 2))

if inContainer; then
    # Build an arm64 chroot if none exists
    test -d "/arm64" || qemu-debootstrap \
    	--arch=arm64 stretch /arm64/stretch http://deb.debian.org/debian/

    # Make the directories that gbp will download repositories to and build in
    mkdir -p /deb
    mkdir -p /build
    mkdir -p /deb/arm64
    mkdir -p /arm64/stretch/deb
    mkdir -p /arm64/stretch/build

    # Mount /deb and /build so we can get at them from inside the chroot
    mount --bind /deb/arm64 /arm64/stretch/deb
    mount --bind /build /arm64/stretch/build

    # Copy signing key into the chroot if available
    [ -f "/keyfile.key" ] && cp /keyfile.key /arm64/stretch/keyfile.key
    # Copy this script into the chroot
    cp "$0" /arm64/stretch
fi

# Change into build directory and set the configuration files
cd /build
set_gbp_config
set_debuild_config

get_update_path tm-librarian.git
( $BUILD ) && ( run_update && gbp buildpackage )

get_update_path l4fame-node.git
( $BUILD ) && ( run_update && gbp buildpackage )

get_update_path l4fame-manager.git
( $BUILD ) && ( run_update && gbp buildpackage )

get_update_path tm-hello-world.git
( $BUILD ) && ( run_update && gbp buildpackage )

get_update_path tm-libfuse.git
( $BUILD ) && ( run_update && gbp buildpackage )

get_update_path libfam-atomic.git
( $BUILD ) && ( run_update && gbp buildpackage --git-upstream-tree=branch )

get_update_path tm-manifesting.git
( $BUILD ) && ( run_update && gbp buildpackage --git-upstream-branch=master --git-upstream-tree=branch )

get_update_path Emulation.git
( $BUILD ) && ( run_update && gbp buildpackage --git-upstream-branch=master )

fix_nvml_rules
get_update_path nvml.git
# ( $BUILD ) && ( run_update && gbp buildpackage --git-prebuild='mv -f /tmp/rules debian/rules' )

# Before doing the kernel, copy all the built .deb's to the external deb folder
cp /gbp-build-area/*.deb /deb
cp /gbp-build-area/*.changes /deb

# Build with config.l4fame in docker and oldconfig in chroot
get_update_path linux-l4fame.git
if $BUILD; then
    cd $GITPATH
    set_kernel_config
    make -j$CORES deb-pkg
    if inContainer; then
        touch ../$(basename $(pwd))-update
    else
        rm ../$(basename $(pwd))-update
    fi
    mv -f /build/linux*.* /gbp-build-area

    # Sign the linux*.changes file if applicable
    [ "$GPGID" ] && ( echo "n" | debsign -k"$GPGID" /gbp-build-area/linux*.changes )
    cp /gbp-build-area/*.deb /deb
    cp /gbp-build-area/*.changes /deb
fi

# Possibly chain this script into the ARM chroot
if inContainer; then
    chroot /arm64/stretch "/$(basename $0)" 'cores=$CORES' 'http_proxy=$http_proxy' 'https_proxy=$https_proxy'
fi
