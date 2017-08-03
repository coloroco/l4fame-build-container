#!/bin/bash
apt-get update && \
apt-get upgrade -y && \
apt-get install -y \
                git \
                libssl-dev \
                kmod \
                cpio \
                bc \
                dpkg-dev \
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

# Set $CORES to half the cpu cores, capped at 8
if [ $(( $(( $((`cat /proc/cpuinfo | grep processor | wc -l`)) + 1 )) / 2 )) -gt "8" ];
    then CORES=8
else
    CORES=$(( $(( $((`cat /proc/cpuinfo | grep processor | wc -l`)) + 1 )) / 2 ))
fi

mkdir /deb;
cd /home;

git clone https://github.com/FabricAttachedMemory/nvml.git && \
(   ( cd nvml && make -j $CORES dpkg );
    ( cd nvml/dpkgbuild/nvml-* && mkdir usr && dpkg-buildpackage --jobs=$CORES -b -us -uc;
    mv debian/tmp/usr/lib64 usr/lib && dpkg-buildpackage --jobs=$CORES -b -us -uc;
    cd .. && cp ./*.deb /deb );
) || \
( cd nvml && set -- `git pull` && [ "$1" == "Updating" ] && \
    ( make -j $CORES dpkg;
    ( cd dpkgbuild/nvml-* && mkdir usr && dpkg-buildpackage --jobs=$CORES -b -us -uc;
    mv debian/tmp/usr/lib64 usr/lib && dpkg-buildpackage --jobs=$CORES -b -us -uc;
    cd .. && cp ./*.deb /deb );
) );

git clone https://github.com/FabricAttachedMemory/tm-librarian.git && \
( cd tm-librarian && dpkg-buildpackage --jobs=$CORES -us -uc ) || \
( cd tm-librarian && set -- `git pull` && [ "$1" == "Updating" ] && dpkg-buildpackage --jobs=$CORES -us -uc );

git clone https://github.com/FabricAttachedMemory/l4fame-node.git && \
( cd l4fame-node && dpkg-buildpackage --jobs=$CORES -us -uc ) || \
( cd l4fame-node && set -- `git pull` && [ "$1" == "Updating" ] && dpkg-buildpackage --jobs=$CORES -us -uc );

git clone https://github.com/FabricAttachedMemory/l4fame-manager.git && \
( cd l4fame-manager && dpkg-buildpackage --jobs=$CORES -us -uc ) || \
( cd l4fame-manager && set -- `git pull` && [ "$1" == "Updating" ] && dpkg-buildpackage --jobs=$CORES -us -uc );

git clone -b debian https://github.com/FabricAttachedMemory/tm-hello-world.git && \
( cd tm-hello-world && dpkg-buildpackage --jobs=$CORES -b -us -uc ) || \
( cd tm-hello-world && set -- `git pull` && [ "$1" == "Updating" ] && dpkg-buildpackage --jobs=$CORES -b -us -uc );

git clone -b debian https://github.com/FabricAttachedMemory/tm-libfuse.git && \
( cd tm-libfuse && dpkg-buildpackage --jobs=$CORES -b -us -uc ) || \
( cd tm-libfuse && set -- `git pull` && [ "$1" == "Updating" ] && dpkg-buildpackage --jobs=$CORES -b -us -uc );

git clone -b upstream https://github.com/FabricAttachedMemory/libfam-atomic.git || \
( cd libfam-atomic && git pull );
git clone https://github.com/FabricAttachedMemory/libfam-atomic.git atomic-deb || \
( cd atomic-deb && git pull );
( cd libfam-atomic && set -- `git pull` && [ "$1" == "Updating" ] && \
        ( cp -r atomic-deb/debian libfam-atomic && cd libfam-atomic && dpkg-buildpackage --jobs=$CORES -us -uc ) );

git clone https://github.com/FabricAttachedMemory/Emulation.git || \
( cd Emulation && git pull );
git clone -b debian https://github.com/keith-packard/Emulation.git Emulation-deb || \
( cd Emulation-deb && git pull );
( cd Emulation && set -- `git pull` && [ "$1" == "Updating" ] && \
        ( cp -r Emulation-deb/debian Emulation && cd Emulation && dpkg-buildpackage --jobs=$CORES -b -us -uc ) );

git clone https://github.com/FabricAttachedMemory/tm-manifesting.git && \
( cd tm-manifesting && dpkg-buildpackage --jobs=$CORES -b -us -uc ) || \
( cd tm-manifesting && set -- `git pull` && [ "$1" == "Updating" ] && dpkg-buildpackage --jobs=$CORES -b -us -uc );

cp /home/*.deb /deb;


git clone https://github.com/FabricAttachedMemory/linux-l4fame.git && \
( cd linux-l4fame && make -j $CORES deb-pkg ) || \
( cd linux-l4fame && set -- `git pull` && [ "$1" == "Updating" ] && make -j $CORES deb-pkg );

cp /home/*.deb /deb;

