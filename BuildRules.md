## Instructions for Building Individual Packages

Each package referenced in builder.bash can be built individually using git-buildpackage (gbp).  Every repo contains a branch with the Debian directive/control files in the "debian" directory.  Unfortunately, each repo uses a slightly different branching scheme.  The main idea is to install prerequisite packages, clone the repo, checkout the appropriate branch, and run "gbp buildpackage".  While the intent of all Debian packaging is to create artifacts suitable for submission to debian.org, these repos are only interested in creating binary .deb package files.  As such, certain liberties and shortcuts may have been taken.

Every repo has a dedicated config file named "debian/gbp.conf".   By default every repo will use scratch space in /tmp/gpb4hpe, which is also where you'll find completed packaging.   To change this, add the option "--git-export-dir=some/where/else".  Other options in the gbp.conf file are beyond the scope of this discussion, however a [very useful GBP art object can be seen here](https://people.debian.org/~stapelberg/2016/11/25/build-tools.html).

---
### Setup and Configuration 
Install `git-buildpackage`
```shell
$ sudo apt-get install git-buildpackage
```

---
### Packages
  * [nvml](#nvml)
  * [tm-librarian](#tm-librarian)
  * [tm-manifesting](#tm-manifesting)
  * [l4fame-node](#l4fame-node)
  * [l4fame-manager](#l4fame-manager)
  * [tm-hello-world](#tm-hello-world)
  * [tm-libfuse](#tm-libfuse)
  * [libfam-atomic](#libfam-atomic)
  * [fame](#fame)
  * [linux-kernel](#linux-kernel)

---
### nvml

nvml is a 2016 snapshot of the [Intel NVML/PMEM project](http://pmem.io/2017/12/11/NVML-is-now-PMDK.html), specifically the libpmem library (the lowest in their stack).  Since then the library has been rechristened [PMDK - Persistent Memory Dev Kit](http://pmem.io/pmdk/).  The FAM project here, nvml, is stale with respect to that effort.
**Packages**
```shell
libpmem_[version].deb 
libpmem-dev_[version].deb
```
**Build Requirements** 
```shell
$ sudo apt-get install uuid-dev 
```

**Build Process**
1. [git clone https://github.com/FabricAttachedMemory/nvml.git](https://github.com/FabricAttachedMemory/nvml.git).
2. Checkout `upstream`, then checkout `debian`.
3. Build with 
```shell
gbp buildpackage
```

---
### tm-librarian
The Librarian suite breaks with Debian tradition in that it only has one branch with source in it ("upstream"), along with another branch ("debian") containing only the Debian directive files.  The use must merge these remote branches into a local-only "master" branch from which the packages can be built.
**Packages**
```shell
tm-librarian_[version].deb 
python3-tm-librarian_[version].deb 
tm-lfs_[version].deb 
```
**Build Requirements** 
```shell
$ sudo apt-get install dh-exec
```
**Build Process**
[git clone https://github.com/FabricAttachedMemory/tm-librarian.git](https://github.com/FabricAttachedMemory/tm-librarian.git).
```shell
[git clone https://github.com/FabricAttachedMemory/tm-librarian.git](https://github.com/FabricAttachedMemory/tm-librarian.git).
git checkout upstream
git checkout debian
git checkout --orphan master
git merge upstream
gbp buildpackage
```

---
### tm-manifesting
**Packages**
```shell
tm-manifesting_[version].deb
```
**Build Requirements** 
```shell
apt-get install dh-exec
```
**Build Process**
1. Clone [this repository](https://github.com/keith-packard/tm-manifesting.git).
2. Build with 
```shell
gbp buildpackage --git-upstream-branch=master --git-upstream-tree=branch
```

---
### l4fame-node
**Packages**
```shell
l4fame-node_[version].deb
```
**Build Requirements**
```shell
# no package requirements
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/l4fame-node.git).
2. Build with
```shell
gbp buildpackage
```

---
### l4fame-manager
**Packages**
```shell
l4fame-manager_[version].deb
```
**Build Requirements**
```shell
# no package requirements
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/l4fame-manager.git).
2. Build with 
```shell
gbp buildpackage
```

---
### tm-hello-world
**Packages**
```shell
tm-hello-world_[version].deb
```
**Build Requirements**
```shell
# no package requirements
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
**Packages**
```shell
tm-libfuse_[version].deb
```
**Build Requirements**
```shell
apt-get install libselinux-dev
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/tm-libfuse.git).
2. Checkout `upstream`, then checkout `debian`.
3. Build with
```shell
gbp buildpackage
```

---
### libfam-atomic
**Packages**
```shell
libfam-atomic2_[version].deb 
libfam-atomic2-dev_[version].deb 
libfam-atomic2-dbg_[version].deb 
libfam-atomic2-tests_[version].deb
```
**Build Requirements**
```shell
apt-get install pkg-config autoconf-archive asciidoc libxml2-utils xsltproc docbook-xsl docbook-xml
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
**Packages**
```shell
fame_[version].deb
```
**Build Requirements**
```shell
# no package requirements
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/Emulation.git).
2. Checkout `debian`.
3. Build with
```shell
gbp buildpackage --git-upstream-branch=master
```

---
### linux-kernel 
**Packages**
```shell
linux-firmware-image-4.8.0-l4fame+_[version].deb
linux-headers-4.8.0-l4fame+_[version].deb 
linux-libc-dev_[version].deb 
linux-image-4.8.0-l4fame+_[version].deb 
linux-image-4.8.0-l4fame+-dbg_[version].deb
```
**Build Requirements**
```shell
apt-get install build-essential bc libssl-dev
```
**Build Process**
1. Clone [this repository](https://github.com/FabricAttachedMemory/linux-l4fame.git).
2. Build with
```shell
make deb-pkg
```

