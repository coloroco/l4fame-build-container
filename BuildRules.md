## Instructions for Building Individual Packages

Each package referenced in builder.bash can be built individually using git-buildpackage (gbp).  Every repo contains a branch with the Debian directive/control files in the "debian" directory.  Unfortunately, each repo uses a slightly different branching scheme.  The main idea is to install prerequisite packages, clone the repo, checkout the appropriate branch, and run "gbp buildpackage".  While the intent of all Debian packaging is to create artifacts suitable for submission to debian.org, these repos are only interested in creating binary .deb package files.  As such, certain liberties and shortcuts may have been taken.

Every repo has a dedicated config file named "debian/gbp.conf".   By default every repo will use scratch space in /tmp/gpb4hpe, which is also where you'll find completed packaging.   To change this, add the option "--git-export-dir=some/where/else".  Other options in the gbp.conf file are beyond the scope of this discussion, however this material helped a lot:

* [very useful GBP art object](https://people.debian.org/~stapelberg/2016/11/25/build-tools.html)

---
### Setup and Configuration 
Install common prerequisites
```shell
$ sudo apt-get install git git-buildpackage uuid-dev dh-exec libselinux-dev
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
uuid-dev 

**Build Process**
```shell
$ git clone https://github.com/FabricAttachedMemory/nvml.git
$ cd nvml
$ git checkout upstream && git checkout debian --
$ gbp buildpackage
```

---
### [tm-librarian](https://github.com/FabricAttachedMemory/tm-librarian.git)
The Librarian suite breaks with Debian tradition in that it only has one branch with source in it ("upstream"), along with another branch ("debian") containing only the Debian directive files.  The user must merge these remote branches into a local-only "master" branch from which the packages can be built.
**Packages**
tm-librarian_[version].deb 
python3-tm-librarian_[version].deb 
tm-lfs_[version].deb 

**Build Requirements** 
dh-exec

**Build Process**
```shell
git clone https://github.com/FabricAttachedMemory/tm-librarian.git
cd tm-librarian
git checkout upstream && git checkout debian --  # Realize local branches
git checkout --orphan master                     # Fork a branch from "debian", then switch to it
git merge upstream                               # Into newly-create "master" branch
gbp buildpackage
```

---
### [tm-manifesting](https://github.com/FabricAttachedMemory/tm-manifesting.git)
**Packages**
tm-manifesting_[version].deb

**Build Requirements** 
dh-exec

**Build Process**
```shell
$ git clone https://github.com/FabricAttachedMemory/tm-manifesting.git
$ cd tm-manifesting
$ git checkout master
$ gbp buildpackage
```

---
### l4fame-node
**Packages**
```shell
l4fame-node_[version].deb
```
**Build Requirements**
Nothing extra

**Build Process**
```shell
$ git clone https://github.com/FabricAttachedMemory/l4fame-node.git
$ cd l4fame-node
$ git checkout master
$ gbp buildpackage
```

---
### l4fame-manager
**Packages**
l4fame-manager_[version].deb

**Build Requirements**
Nothing extra

**Build Process**
```shell
$ git clone https://github.com/FabricAttachedMemory/l4fame-manager.git
$ cd l4fame-manager
$ git checkout master
$ gbp buildpackage
```

---
### tm-hello-world
**Packages**
tm-hello-world_[version].deb

**Build Requirements**
Nothing extra

**Build Process**
```shell
$ git clone https://github.com/FabricAttachedMemory/tm-hello-world.git
$ cd tm-hello-world
$ git checkout debian --
$ gbp buildpackage
```

---
### tm-libfuse
**Packages**
tm-libfuse_[version].deb

**Build Requirements**
libselinux-dev

**Build Process**
```shell
$ git clone https://github.com/FabricAttachedMemory/tm-libfuse.git
$ cd tm-libfuse
$ git checkout upstream && git checkout debian --
$ gbp buildpackage
```

---
### libfam-atomic
**Packages**
libfam-atomic2_[version].deb 
libfam-atomic2-dev_[version].deb 
libfam-atomic2-dbg_[version].deb 
libfam-atomic2-tests_[version].deb

**Build Requirements**
pkg-config autoconf-archive asciidoc libxml2-utils xsltproc docbook-xsl docbook-xml

**Build Process**
```shell
$ git clone https://github.com/FabricAttachedMemory/libfam-atomic.git
$ cd libfam-atomic
$ git checkout upstream && git checkout debian --
$ gbp buildpackage --git-upstream-tree=branch
```

---
### linux-kernel 
The kernel has its own mechanism for building a Debian package and does not use gbp.
**Packages**
linux-firmware-image-4.14y_[version].deb
linux-headers-4.14y_[version].deb 
linux-libc-dev_[version].deb 
linux-image-4.14y_[version].deb 
linux-image-4.14y-dbg_[version].deb

**Build Requirements**
build-essential bc libssl-dev

**Build Process**
```shell
$ git clone https://github.com/FabricAttachedMemory/linux-l4fame.git
$ cd linux-l4fame
$ git checkout mdc/linux-4.14.y
$ cp config.amd64-fame .config
$ scripts/config --disable DEBUG_INFO   # Suppress debug kernel
$ rm -f .version
$ make -j50 deb-pkg  # Replace "50" with however many cores you have to spare
```
