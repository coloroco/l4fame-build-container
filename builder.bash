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
    ( gbp buildpackage $* );
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

# Old pathway
git clone https://github.com/FabricAttachedMemory/nvml.git && \
(   ( cd nvml && make -j $CORES BUILD_PACKAGE_CHECK=n dpkg );
    ( cd nvml/dpkgbuild/nvml-* && run_update );
    ( cd nvml && rm -rf dpkgbuild && make -j $CORES BUILD_PACKAGE_CHECK=n dpkg );
    ( cd nvml/dpkgbuild/nvml-* && mkdir -p usr && mv debian/tmp/usr/lib64 usr/lib && \
        ( run_update;
        dpkg-buildpackage --jobs=$CORES -b -us -uc;
        check_build_error; ); cp ../*.deb /deb );
) || \
( cd nvml && set -- `git pull` && [ "$1" == "Updating" ] && \
    ( ( cd nvml/dpkgbuild/nvml-* && run_update );
    ( rm -rf dpkgbuild && make -j $CORES BUILD_PACKAGE_CHECK=n dpkg;
    ( cd dpkgbuild/nvml-* && mkdir -p usr && mv debian/tmp/usr/lib64 usr/lib && \
        ( run_update;
        dpkg-buildpackage --jobs=$CORES -b -us -uc;
        check_build_error; ); cp ../*.deb /deb );
) ) || ( cp dpkgbuild/*.deb /deb ); );


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
( cd linux-l4fame && ( make -j $CORES deb-pkg;
    check_build_error; ); ) || \
( cd linux-l4fame && set -- `git pull` && [ "$1" == "Updating" ] && ( make -j $CORES deb-pkg;
    check_build_error; ); );
cp /build/*.deb /deb;


