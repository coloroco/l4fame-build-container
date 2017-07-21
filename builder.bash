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
                                xsltproc \
                                docbook-xsl \
                                docbook-xml;

cd /tmp;
mkdir dpkg-build;
cd dpkg-build;
git clone https://github.com/FabricAttachedMemory/tm-librarian.git && \
cd tm-librarian && dpkg-buildpackage -b -rfakeroot -us -uc;
cd /tmp;
git clone https://github.com/FabricAttachedMemory/l4fame-node.git && \
cd l4fame-node && dpkg-buildpackage -b -rfakeroot -us -uc;
cd /tmp;
git clone https://github.com/FabricAttachedMemory/l4fame-manager.git && \
cd l4fame-manager && dpkg-buildpackage -b -rfakeroot -us -uc;
cd /tmp;
git clone https://github.com/AustinHunting/libfam-atomic.git && \
cd libfam-atomic && dpkg-buildpackage -b -rfakeroot -us -uc;
cd /tmp;
git clone -b debian https://github.com/keith-packard/Emulation.git && \
cd Emulation && dpkg-buildpackage -b -rfakeroot -us -uc;
cd /tmp;
git clone -b debian https://github.com/FabricAttachedMemory/tm-hello-world.git && \
cd tm-hello-world && dpkg-buildpackage -b -rfakeroot -us -uc;
cd /tmp;
git clone -b debian https://github.com/FabricAttachedMemory/tm-libfuse.git && \
cd tm-libfuse && dpkg-buildpackage -b -rfakeroot -us -uc;
cd /tmp && cp ./*.deb /deb;
cd /tmp && rm -rf dpkg-build;

git clone https://github.com/FabricAttachedMemory/nvml.git && \
cd nvml && make dpkg;
cd dpkgbuild/nvml-*;
mkdir usr && dpkg-buildpackage -b -rfakeroot -us -uc;
mv debian/tmp/usr/lib64 usr/lib
dpkg-buildpackage -b -rfakeroot -us -uc;
cd .. && cp ./*.deb /deb;
cd /tmp && rm -rf nvml;

git clone https://github.com/FabricAttachedMemory/linux-l4fame.git && \
cd linux-l4fame && fakeroot make deb-pkg;
cd /tmp && cp ./*.deb /deb;

