## Instructions for Building Individual Packages

Each package referenced in builder.bash can be built individually using the following steps:


| Package | Build Process | Package Requirements |
| --- | --- | --- |
| **tm-libfuse** | 1. Clone the [debian branch](https://github.com/FabricAttachedMemory/tm-libfuse.git)<br>2. Build with `dpkg-buildpackage -b -us -uc` | `build-essential`<br>`dh-autoreconf`<br>`libselinux-dev` |
| **libfam-atomic** | 1. Clone the [master branch](https://github.com/FabricAttachedMemory/libfam-atomic.git) and the [upstream branch](https://github.com/FabricAttachedMemory/libfam-atomic/tree/upstream)<br>2. Move the debian folder from master to upstream.<br>3. Build in upstream with `dpkg-buildpackage -us -uc` | `build-essential`<br>`pkg-config`<br>`libtool`<br>`automake`<br>`autoconf-archive`<br>`asciidoc`<br>`libxml2-utils`<br>`xsltproc`<br>`xml-core`<br>`docbook-xsl`<br>`docbook-xml`<br>`debhelper` |
| **librarian** | 1. Clone the [master branch](https://github.com/FabricAttachedMemory/tm-librarian.git)<br>2. Build with `dpkg-buildpackage -us -uc`  | `build-essential`<br>`dh-exec`<br>`dh-python` |
| **l4fame-node** | 1. Clone the [master branch](https://github.com/FabricAttachedMemory/l4fame-node.git)<br>2. Build with `dpkg-buildpackage -us -uc` | `build-essential`<br>`debhelper` |
| **l4fame-manager** | 1. Clone the [master branch](https://github.com/FabricAttachedMemory/l4fame-manager.git)<br>2. Build with `dpkg-buildpackage -us -uc` | `build-essential`<br>`debhelper` |
| **Emulation** | 1. Clone the [master branch](https://github.com/FabricAttachedMemory/Emulation.git) and the [debian branch](https://github.com/FabricAttachedMemory/Emulation/tree/debian)<br>2. Move the debian folder from debian to master.<br>3. Build in master with `dpkg-buildpackage -b -us -uc` | `build-essential`<br>`debhelper` |
| **tm-hello-world** | 1. Clone the [debian branch](https://github.com/FabricAttachedMemory/tm-hello-world/tree/debian)<br>2. Build with `dpkg-buildpackage -b -us -uc` | `build-essential`<br>`debhelper` |
| **nvml** | 1. Clone the [master branch](https://github.com/FabricAttachedMemory/nvml.git)<br>2. Run `make dpkg`, expect it to fail.<br>3. `cd` into `dpkgbuild/nvml-*` and run `mkdir usr`<br>4. Move `debian/tmp/usr/lib64` into `usr/lib`.<br>5. Build with `dpkg-buildpackage -b -us -uc` | `build-essential`<br>`pkg-config`<br>`devscripts`<br>`doxygen` |
| **linux-l4fame** | 1. Clone the [master branch](https://github.com/FabricAttachedMemory/linux-l4fame.git)<br>2. Build with `make deb-pkg` | `build-essential`<br>`bc`<br>`libssl-dev` |
| **tm-manifesting** | 1. Clone the [master branch](https://github.com/FabricAttachedMemory/tm-manifesting.git)<br>2. Build with `dpkg-buildpackage -b -us -uc` | `build-essential`<br>`debhelper`<br>`dh-exec`<br>`python-all`<br>`dh-python` |
