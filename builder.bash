#!/bin/bash
# install updates
apt update && \
apt upgrade -y && \
apt install -y git-buildpackage;
apt install -y libssl-dev bc pkg-config build-essential

# Sets the configuration files for devbuilder and gbp
set_config_files () {
cat <<EOF > $HOME/.gbp.conf
[DEFAULT]
cleaner = fakeroot debian/rules clean
ignore-new = True

[buildpackage]
export-dir = /build-area/
tarball-dir = /tarballs/

[git-import-orig]
dch = False
EOF

cat <<EOF > $HOME/.devscripts
DEBUILD_DPKG_BUILDPACKAGE_OPTS="-us -uc -i -b --jobs=$CORES"
EOF
}

# Checks for needed build packages and installs them
run_update () {
    ( ls debian &>/dev/null ) && \
    ( ( dpkg-checkbuilddeps &>/dev/null ) || \
    ( echo "y" | mk-build-deps -i -r ) )
}

# Builds packages
run_builder () {
    ( git checkout debian );
    ( run_update );
    ( gbp buildpackage "$*" );
}

# Builds a new debian/rules file for nvml
fix_nvml_rules () {
read -r -d '' rule<<"EOF"
#!/usr/bin/make -f
%:
\tdh \$@

override_dh_auto_install:
\tdh_auto_install -- prefix=/usr

override_dh_install:
\tmkdir -p debian/tmp/usr/share/nvml/
\tcp utils/nvml.magic debian/tmp/usr/share/nvml/
\tmv debian/tmp/usr/lib64 debian/tmp/usr/lib
\tdh_install

override_dh_auto_test:
\techo "We do not test this code yet."

override_dh_clean:
\tfind src/ -name 'config.status' -delete
\tfind src/ -name 'config.log' -delete
\tdh_clean
EOF
echo -e "$rule" > /tmp/rules
}


# If user sets "-e cores=number_of_cores" use that many cores to compile
if [ "$cores" ]; then
    CORES=$(( $cores ))
# Set $CORES to half the cpu cores, capped at 8
else
    if [ $(( ( `nproc` + 1 ) / 2 )) -gt "8" ];
        then CORES=8
    else
        CORES=$(( ( `nproc` + 1 ) / 2 ))
    fi
fi


mkdir -p /deb;
mkdir -p /build;
cd /build;

set_config_files;

# git checkout debian && apply new rules file && --git-prebuild='mv /tmp/rules debian/rules'
git clone https://github.com/FabricAttachedMemory/nvml.git && \
    ( cd nvml && git checkout upstream && fix_nvml_rules && run_builder --git-prebuild='mv /tmp/rules debian/rules' ) || \
    ( cd nvml && git checkout upstream && fix_nvml_rules && set -- `git pull` && [ "$1" == "Updating" ] && run_builder --git-prebuild='mv /tmp/rules debian/rules' )

# git checkout debian && run_builder
git clone https://github.com/keith-packard/tm-librarian.git && \
    ( cd tm-librarian && run_builder ) || \
    ( cd tm-librarian && set -- `git pull` && [ "$1" == "Updating" ] && run_builder )


# run_builder && gbp buildpackage --git-upstream-branch=master --git-upstream-tree=branch
git clone https://github.com/keith-packard/tm-manifesting.git && \
    ( cd tm-manifesting && run_builder --git-upstream-branch=master --git-upstream-tree=branch ) || \
    ( cd tm-manifesting && set -- `git pull` && [ "$1" == "Updating" ] && run_builder --git-upstream-branch=master --git-upstream-tree=branch )

# git checkout debian && run_builder
git clone https://github.com/FabricAttachedMemory/l4fame-node.git && \
    ( cd l4fame-node && run_builder ) || \
    ( cd l4fame-node && set -- `git pull` && [ "$1" == "Updating" ] && run_builder )

# git checkout debian && run_builder
git clone https://github.com/FabricAttachedMemory/l4fame-manager.git && \
    ( cd l4fame-manager && run_builder ) || \
    ( cd l4fame-manager && set -- `git pull` && [ "$1" == "Updating" ] && run_builder )

# git checkout debian && run_builder
git clone https://github.com/FabricAttachedMemory/tm-hello-world.git && \
    ( cd tm-hello-world && run_builder ) || \
    ( cd tm-hello-world && set -- `git pull` && [ "$1" == "Updating" ] && run_builder )

# git checkout upstream && git checkout debian && run_builder
git clone https://github.com/FabricAttachedMemory/tm-libfuse.git && \
    ( cd tm-libfuse && git checkout upstream && run_builder ) || \
    ( cd tm-libfuse && git checkout upstream && set -- `git pull` && [ "$1" == "Updating" ] && run_builder )

# git checkout upstream && git checkout debian && gbp buildpackage --git-upstream-tree=branch
git clone https://github.com/FabricAttachedMemory/libfam-atomic.git && \
    ( cd libfam-atomic && git checkout upstream && run_builder --git-upstream-tree=branch ) || \
    ( cd libfam-atomic && git checkout upstream && set -- `git pull` && [ "$1" == "Updating" ] && run_builder --git-upstream-tree=branch )

# git checkout debian && gbp buildpackage --git-upstream-branch=master
git clone https://github.com/FabricAttachedMemory/Emulation.git && \
    ( cd Emulation && run_builder --git-upstream-branch=master ) || \
    ( cd Emulation && set -- `git pull` && [ "$1" == "Updating" ] && run_builder --git-upstream-branch=master )

# copy all .debs to external deb folder
cp /build-area/*.deb /deb;

# Old pathway
git clone https://github.com/FabricAttachedMemory/linux-l4fame.git && \
    ( cd linux-l4fame && make -j $CORES deb-pkg || \
    ( cd linux-l4fame && set -- `git pull` && [ "$1" == "Updating" ] && make -j $CORES deb-pkg );
cp /build/*.deb /deb;


