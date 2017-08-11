#!/bin/bash
apt-get update && \
apt-get upgrade -y && \
apt-get install -y \
                git \
                libssl-dev \
                kmod \
                cpio \
                bc \
                uuid-dev \
                pkg-config \
                devscripts \
                build-essential \
                debhelper \
                doxygen \
                dh-exec \
                dh-python \
                libselinux-dev \
                autoconf-archive \
                asciidoc \
                libxml2-utils \
                xsltproc \
                docbook-xsl \
                docbook-xml \
                dh-python \
                python-all;

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

# Prints ERROR and working directory if a build fails
check_build_error () {
    if [ "$?" -ne "0" ]; then
        echo ""
        echo "ERROR: Building died at this package"
        echo "ERROR: `pwd`"
        echo ""
    fi
}

mkdir -p /deb;
mkdir -p /build;
cd /build;

git clone https://github.com/FabricAttachedMemory/nvml.git && \
(   ( cd nvml && make -j $CORES BUILD_PACKAGE_CHECK=n dpkg );
    ( cd nvml/dpkgbuild/nvml-* && mkdir -p usr && mv debian/tmp/usr/lib64 usr/lib && \
        ( dpkg-buildpackage --jobs=$CORES -b -us -uc;
        check_build_error; ); cp ../*.deb /deb );
) || \
( cd nvml && set -- `git pull` && [ "$1" == "Updating" ] && \
    ( rm -rf dpkgbuild && make -j $CORES BUILD_PACKAGE_CHECK=n dpkg;
    ( cd dpkgbuild/nvml-* && mkdir -p usr && mv debian/tmp/usr/lib64 usr/lib && \
        ( dpkg-buildpackage --jobs=$CORES -b -us -uc;
        check_build_error; ); cp ../*.deb /deb );
) || ( cp dpkgbuild/*.deb /deb ); );

git clone https://github.com/FabricAttachedMemory/tm-librarian.git && \
( cd tm-librarian && ( dpkg-buildpackage --jobs=$CORES -us -uc;
    check_build_error; ); ) || \
( cd tm-librarian && set -- `git pull` && [ "$1" == "Updating" ] && ( dpkg-buildpackage --jobs=$CORES -us -uc;
    check_build_error; ); );

git clone https://github.com/FabricAttachedMemory/l4fame-node.git && \
( cd l4fame-node && ( dpkg-buildpackage --jobs=$CORES -us -uc;
    check_build_error; ); ) || \
( cd l4fame-node && set -- `git pull` && [ "$1" == "Updating" ] && ( dpkg-buildpackage --jobs=$CORES -us -uc;
    check_build_error; ); );

git clone https://github.com/FabricAttachedMemory/l4fame-manager.git && \
( cd l4fame-manager && ( dpkg-buildpackage --jobs=$CORES -us -uc;
    check_build_error; ); ) || \
( cd l4fame-manager && set -- `git pull` && [ "$1" == "Updating" ] && ( dpkg-buildpackage --jobs=$CORES -us -uc;
    check_build_error; ); );

git clone -b debian https://github.com/FabricAttachedMemory/tm-hello-world.git && \
( cd tm-hello-world && ( dpkg-buildpackage --jobs=$CORES -b -us -uc;
    check_build_error; ); ) || \
( cd tm-hello-world && set -- `git pull` && [ "$1" == "Updating" ] && ( dpkg-buildpackage --jobs=$CORES -b -us -uc;
    check_build_error; ); );

git clone -b debian https://github.com/FabricAttachedMemory/tm-libfuse.git && \
( cd tm-libfuse && ( dpkg-buildpackage --jobs=$CORES -b -us -uc;
    check_build_error; ); ) || \
( cd tm-libfuse && set -- `git pull` && [ "$1" == "Updating" ] && ( dpkg-buildpackage --jobs=$CORES -b -us -uc;
    check_build_error; ); );

git clone https://github.com/FabricAttachedMemory/libfam-atomic.git atomic-deb || \
( cd atomic-deb && git pull );
git clone -b upstream https://github.com/FabricAttachedMemory/libfam-atomic.git && \
( cp -r atomic-deb/debian libfam-atomic && cd libfam-atomic && ( dpkg-buildpackage --jobs=$CORES -us -uc;
    check_build_error; ); ) || \
( cp -r atomic-deb/debian libfam-atomic && cd libfam-atomic && set -- `git pull` && [ "$1" == "Updating" ] && \
        ( dpkg-buildpackage --jobs=$CORES -us -uc;
            check_build_error; ); );

git clone -b debian https://github.com/FabricAttachedMemory/Emulation.git Emulation-deb || \
( cd Emulation-deb && git pull );
git clone https://github.com/FabricAttachedMemory/Emulation.git && \
( cp -r Emulation-deb/debian Emulation && cd Emulation && ( dpkg-buildpackage --jobs=$CORES -b -us -uc;
    check_build_error; ); ) || \
( cp -r Emulation-deb/debian Emulation && cd Emulation && set -- `git pull` && [ "$1" == "Updating" ] && \
        ( dpkg-buildpackage --jobs=$CORES -b -us -uc;
            check_build_error; ); );

git clone https://github.com/FabricAttachedMemory/tm-manifesting.git && \
( cd tm-manifesting && ( dpkg-buildpackage --jobs=$CORES -b -us -uc;
    check_build_error; ); ) || \
( cd tm-manifesting && set -- `git pull` && [ "$1" == "Updating" ] && ( dpkg-buildpackage --jobs=$CORES -b -us -uc;
    check_build_error; ); );

cp /build/*.deb /deb;


git clone https://github.com/FabricAttachedMemory/linux-l4fame.git && \
( cd linux-l4fame && ( make -j $CORES deb-pkg;
    check_build_error; ); ) || \
( cd linux-l4fame && set -- `git pull` && [ "$1" == "Updating" ] && ( make -j $CORES deb-pkg;
    check_build_error; ); );

cp /build/*.deb /deb;

