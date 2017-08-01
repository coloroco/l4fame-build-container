#!/bin/bash
apt-get update && apt-get install -y \
                                nano \
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
                                graphviz \
                                dh-exec \
                                dh-python \
                                libselinux-dev \
                                autoconf-archive \
                                asciidoc \
                                libxml2-utils \
                                xsltproc
                                docbook-xsl \
                                docbook-xml \
                                xz-utils;

cd /home;

rm -rf nvml && git clone https://github.com/FabricAttachedMemory/nvml.git;
( cd nvml && make dpkg );
( cd nvml/dpkgbuild/nvml-* && mkdir usr && dpkg-buildpackage -b -us -uc;
mv debian/tmp/usr/lib64 usr/lib && dpkg-buildpackage -b -us -uc;
cd .. && mv ./*.deb /deb );

git clone https://github.com/FabricAttachedMemory/tm-librarian.git && \
( cd tm-librarian && dpkg-buildpackage -us -uc ) || \
( cd tm-librarian && git pull && dpkg-buildpackage -us -uc );

git clone https://github.com/FabricAttachedMemory/l4fame-node.git && \
( cd l4fame-node && dpkg-buildpackage -us -uc ) || \
( cd l4fame-node && git pull && dpkg-buildpackage -us -uc );

git clone https://github.com/FabricAttachedMemory/l4fame-manager.git && \
( cd l4fame-manager && dpkg-buildpackage -us -uc ) || \
( cd l4fame-manager && git pull && dpkg-buildpackage -us -uc );

git clone -b debian https://github.com/FabricAttachedMemory/tm-hello-world.git && \
( cd tm-hello-world && dpkg-buildpackage -b -us -uc ) || \
( cd tm-hello-world && git pull && dpkg-buildpackage -b -us -uc );

git clone -b debian https://github.com/FabricAttachedMemory/tm-libfuse.git && \
( cd tm-libfuse && dpkg-buildpackage -b -us -uc ) || \
( cd tm-libfuse && git pull && dpkg-buildpackage -b -us -uc );

git clone -b upstream https://github.com/FabricAttachedMemory/libfam-atomic.git || \
( cd libfam-atomic && git pull );
git clone https://github.com/FabricAttachedMemory/libfam-atomic.git atomic-deb || \
( cd atomic-deb && git pull );
( cp -r atomic-deb/debian libfam-atomic && cd libfam-atomic && dpkg-buildpackage -us -uc );

git clone https://github.com/FabricAttachedMemory/Emulation.git || \
( cd Emulation && git pull );
git clone -b debian https://github.com/keith-packard/Emulation.git Emulation-deb || \
( cd Emulation-deb && git pull );
( cp -r Emulation-deb/debian Emulation && cd Emulation && dpkg-buildpackage -b -us -uc );

mv /home/*.deb /deb;

git clone https://github.com/FabricAttachedMemory/linux-l4fame.git || \
( cd linux-l4fame && git pull );
( cd linux-l4fame && make deb-pkg );

mv /home/*.deb /deb;
rm -rf linux-l4fame;

