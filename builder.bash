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
rm -rf /home/*;

git clone https://github.com/FabricAttachedMemory/nvml.git && \
cd nvml && make dpkg;
cd dpkgbuild/nvml-*;
mkdir usr && dpkg-buildpackage -b -us -uc;
mv debian/tmp/usr/lib64 usr/lib;
dpkg-buildpackage -b -us -uc;
cd .. && cp ./*.deb /deb;
cd /home && rm -rf nvml;

mkdir dpkg-build;
cd dpkg-build;
git clone https://github.com/FabricAttachedMemory/tm-librarian.git && \
cd tm-librarian && dpkg-buildpackage -us -uc;
cd /home;
git clone https://github.com/FabricAttachedMemory/l4fame-node.git && \
cd l4fame-node && dpkg-buildpackage -us -uc;
cd /home;
git clone https://github.com/FabricAttachedMemory/l4fame-manager.git && \
cd l4fame-manager && dpkg-buildpackage -us -uc;
cd /home;
git clone https://github.com/FabricAttachedMemory/libfam-atomic.git deb && \
git clone -b upstream https://github.com/FabricAttachedMemory/libfam-atomic.git && \
mv deb/debian libfam-atomic && cd libfam-atomic && dpkg-buildpackage -us -uc;
cd /home;
git clone -b debian https://github.com/keith-packard/Emulation.git deb && \
git clone https://github.com/FabricAttachedMemory/Emulation.git && \
mv deb/debian Emulation && cd Emulation && dpkg-buildpackage -b -us -uc;
cd /home;
git clone -b debian https://github.com/FabricAttachedMemory/tm-hello-world.git && \
cd tm-hello-world && dpkg-buildpackage -b -us -uc;
cd /home;
git clone -b debian https://github.com/FabricAttachedMemory/tm-libfuse.git && \
cd tm-libfuse && dpkg-buildpackage -b -us -uc;
cd /home && cp ./*.deb /deb;
cd /home && rm -rf dpkg-build;

git clone https://github.com/FabricAttachedMemory/linux-l4fame.git && \
cd linux-l4fame && make deb-pkg;
cd /home && cp ./*.deb /deb;
rm -rf linux-l4fame;

