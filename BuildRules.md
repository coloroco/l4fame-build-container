## Instructions for Building Individual Packages

Each package referenced in builder.bash can be built individually using the following steps:


| Package | Build Process | Package Requirements |
| --- | --- | --- |
| **tm-libfuse** | 1. Clone the debian branch<br>2. Build with `dpkg-buildpackage -b -us -uc` | `build-essential`<br>`dh-autoreconf`<br>`libselinux-dev` |
| **libfam-atomic** | 1. Clone the master branch and the upstream branch.<br>2. Move the debian folder from master to upstream.<br>3. Build in upstream with `dpkg-buildpackage -us -uc` | `build-essential`<br>`pkg-config`<br>`libtool`<br>`automake`<br>`autoconf-archive`<br>`asciidoc`<br>`libxml2-utils`<br>`xsltproc`<br>`xml-core`<br>`docbook-xsl`<br>`docbook-xml`<br>`debhelper` |
| **librarian** | 1. Build with `dpkg-buildpackage -us -uc`  | `build-essential`<br>`dh-exec`<br>`dh-python` |
| **l4fame-node** | 1. Build with `dpkg-buildpackage -us -uc` | `build-essential`<br>`debhelper` |
| **l4fame-manager** | 1. Build with `dpkg-buildpackage -us -uc` | `build-essential`<br>`debhelper` |
| **Emulation** | 1. Clone the debian branch from [This Repository](https://github.com/keith-packard/Emulation.git)<br>2. Clone the master branch<br>3. Move the debian folder from debian to master.<br>4. Build in master with `dpkg-buildpackage -b -us -uc` | `build-essential`<br>`debhelper` |
| **tm-hello-world** | 1. Clone the debian branch<br>2. Build with `dpkg-buildpackage -b -us -uc` | `build-essential`<br>`debhelper` |
| **nvml** | 1. Run make dpkg, expect it to fail.<br>2. cd into dpkgbuild/nvml-*, and build with `dpkg-buildpackage -b -us -uc` expect it to fail.<br>3. Run `mkdir usr` and move debian/tmp/usr/lib64 to usr/lib.<br>4. Run `dpkg-buildpackage -b -us -uc` again. | `build-essential`<br>`pkg-config`<br>`devscripts`<br>`doxygen`<br>`make` |
| **linux-l4fame** | 1. Build with `make deb-pkg` | `make`<br>`gcc`<br>`bc`<br>`libssl-dev`<br>`xz-utils`<br>`dpkg-dev` |