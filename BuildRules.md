## Instructions for Building Individual Packages

Each package referenced in builder.bash can be built individually using the following steps:

---
### Setup and Configuration 
Install `git-buildpackage`, it is required for building all packages.
```shell
apt-get install git-buildpackage
```

Add the following configuration to `~/.devscripts`.
```shell
DEBUILD_DPKG_BUILDPACKAGE_OPTS="-us -uc -i -b"
```

Add the following configuration to `~/.gbp.conf`.
```shell
[DEFAULT]
cleaner = fakeroot debian/rules clean
ignore-new = True

[buildpackage]
export-dir = ../build-area/

[git-import-orig]
dch = False
```

---
### Packages
  * [nvml, libpmem, libpmem-dev](#nvml--libpmem--libpmem-dev)
  * [tm-librarian, python3-tm-librarian, tm-lfs, tm-utils, tm-lmp](#tm-librarian--python3-tm-librarian--tm-lfs--tm-utils--tm-lmp)
  * [tm-manifesting](#tm-manifesting)
  * [l4fame-node](#l4fame-node)
  * [l4fame-manager](#l4fame-manager)
  * [tm-hello-world](#tm-hello-world)
  * [tm-libfuse](#tm-libfuse)
  * [libfam-atomic2, libfam-atomic2-dev, libfam-atomic2-dbg, libfam-atomic2-tests](#libfam-atomic2--libfam-atomic2-dev--libfam-atomic2-dbg--libfam-atomic2-tests)
  * [fame](#fame)
  * [linux-firmware-image-4.8.0-l4fame+, linux-headers-4.8.0-l4fame+, linux-libc-dev, linux-image-4.8.0-l4fame+, linux-image-4.8.0-l4fame+-dbg](#linux-firmware-image-480-l4fame---linux-headers-480-l4fame---linux-libc-dev--linux-image-480-l4fame---linux-image-480-l4fame--dbg)

---
### nvml, libpmem, libpmem-dev
**Packages Required for Building** 
```
uuid-dev 
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/nvml.git).
2. Checkout `upstream`, then checkout `debian`.
3. Build with 
```shell
gbp buildpackage
```

**Note**
If the build fails with the following error,
```shell
gbp:error: 'debuild -i -I' failed: it exited with 29
```
It is because one of the sub-folders in `../build-area/` is misnamed. To fix this error, run the following to build with a new `rules` file.
```shell
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
chmod +x /tmp/rules

gbp buildpackage --git-prebuild='mv /tmp/rules debian/rules'
```

---
### tm-librarian, python3-tm-librarian, tm-lfs, tm-utils, tm-lmp
**Packages Required for Building** 
```
dh-exec
```
**Build Process**
1. Clone [this repository](https://github.com/keith-packard/tm-librarian.git).
2. Checkout `upstream`, then checkout `debian`.
3. Build with 
```shell
gbp buildpackage
```

---
### tm-manifesting
**Packages Required for Building** 
```
dh-exec
```
**Build Process**
1. Clone [this repository](https://github.com/keith-packard/tm-manifesting.git).
2. Build with 
```shell
gbp buildpackage --git-upstream-branch=master --git-upstream-tree=branch
```

---
### l4fame-node
**Packages Required for Building**
```shell
None
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/l4fame-node.git).
2. Build with
```shell
gbp buildpackage
```

---
### l4fame-manager
**Packages Required for Building**
```shell
none
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/l4fame-manager.git).
2. Build with 
```sell
gbp buildpackage
```

---
### tm-hello-world
**Packages Required for Building**
```shell
none
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/tm-hello-world.git).
2. Checkout `debian`.
3. Build with
```shell
gbp buildpackage
```

---
### tm-libfuse
**Packages Required for Building**
```shell
libselinux-dev
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/tm-libfuse.git).
2. Checkout `upstream`, then checkout `debian`.
3. Build with
```shell
gbp buildpackage
```

---
### libfam-atomic2, libfam-atomic2-dev, libfam-atomic2-dbg, libfam-atomic2-tests
**Packages Required for Building**
```shell
pkg-config autoconf-archive asciidoc libxml2-utils xsltproc docbook-xsl docbook-xml
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/libfam-atomic.git).
2. Checkout `upstream`, then checkout `debian`.
3. Build with
```shell
gbp buildpackage --git-upstream-tree=branch
```

---
### fame 
**Packages Required for Building**
```shell
none
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/Emulation.git).
2. Checkout `debian`.
3. Build with
```shell
gbp buildpackage --git-upstream-branch=master
```

---
### linux-firmware-image-4.8.0-l4fame+, linux-headers-4.8.0-l4fame+, linux-libc-dev, linux-image-4.8.0-l4fame+, linux-image-4.8.0-l4fame+-dbg
**Packages Required for Building**
```shell
build-essential bc libssl-dev
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/linux-l4fame.git).
2. Building with
```shell
make deb-pkg
```

