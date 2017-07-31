## Instructions for Building Individual Packages

Each package referenced in builder.bash can be built individually using the following steps:


| Package | Prerequisites for building | Build with | Extra steps |
| ------- | -------------------------- | ---------- | ----------- |
| librarian | build-essential dh-exec dh-python | `dpkg-buildpackage -us -uc` | none |
| l4fame-node | build-essential debhelper | `dpkg-buildpackage -us -uc` | none |
| l4fame-manager | build-essential debhelper | `dpkg-buildpackage -us -uc` | none |
| libfam-atomic | build-essential pkg-config libtool automake autoconf-archive asciidoc libxml2-utils xsltproc xml-core docbook-xsl docbook-xml debhelper | `dpkg-buildpackage -us -uc` | Clone master branch and upstream branch. Move debian folder from master to upstream. Build in upstream. |
| Emulation | build-essential debhelper | `dpkg-buildpackage -b -us -uc` | Clone [this](https://github.com/keith-packard/Emulation.git) branch debian and FAM master. Move debian folder to master. Build in master. |
| tm-hello-world | build-essential debhelper | `dpkg-buildpackage -b -us -uc` | Clone the debian branch. |
| tm-libfuse | build-essential dh-autoreconf libselinux-dev | `dpkg-buildpackage -b -us -uc` | Clone the debian branch. |
| nvml | build-essential pkg-config devscripts doxygen make | `make dpkg && dpkg-buildpackage -b -us -uc` | Run make dpkg, expect it to fail. cd into dpkgbuild/nvml-*, and build with "dpkg-buildpackage -b -us -uc" expect it to fail. Run "mkdir usr", move debian/tmp/usr/lib64 to usr/lib. Then run "dpkg-buildpackage -b -us -uc" again. |
| linux-l4fame | make gcc | `make deb-pkg` | none |
