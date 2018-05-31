# L4fame Build Container

This repository contains a bash script and Dockerfile that will pull and build the Fabric Attached Memory packages necessary for running code on The Machine, FAME (Fabric Attached Memory Emulation), and various SuperDome products.  [These packages are all in Github under the Fabric Attached Memory organization](https://github.com/FabricAttachedMemory).

### Known Working Environments
This build container has been tested and verified working on the following operating systems :
- Red Hat Enterprise Linux 7.3
- Ubuntu 17.04
- Fedora 26
- Debian Jessie and Stretch

## Getting Started

This repository should be cloned and built locally.

### Set up your firewall proxies

If you are behind a corporate firewall, Docker needs to know.
[This article](https://elegantinfrastructure.com/docker/ultimate-guide-to-docker-http-proxy-configuration/)
explains it all.

### Clone & build the Docker image

Clone and build the repository with:

```
git clone git@github.com:FabricAttachedMemory/l4fame-build-container.git
cd l4fame-build-container && docker build --tag l4fame-build .
```

If you're behind a firewall and have the standard environment variables set, add

```
--build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy
```
to the arguments.

## Launching the Docker container

Once the Docker image has been built it needs to be run. First create an empty directory in $HOME to hold the results:

```
mkdir -m777 $HOME/theDebs
```

Run the container:
```
docker run -t --name l4fame-build --privileged -v ~/theDebs:/debs -v L4FAME_BUILD:/build l4fame-build
```

If you're behind a firewall and have the standard environment variables set, add

```
--env http_proxy=$http_proxy --env https_proxy=$https_proxy
```
to the arguments.

To disconnect from the container without killing it, type `Ctrl+C` in the
window in which you executed "docker run ..."

To reconnect to the container run `docker attach l4fame-builder`


| Docker Flag | Explanation |
| ----------- | ----------- |
| `-t` | Allocates and attaches a pseudo-tty, this allows the container to be killed (ctl-C) or sent to the background. |
| `--name l4fame-build` | Names the container "l4fame-build" to simplify subsequent runs. |
| `--privileged` | Gives the container enough privileges to enter a chroot and build arm64 packages. |
| `-v L4FAME_BUILD:/build` | Creates a new Docker volume named L4FAME_BUILD to hold packages and temporary files as they are being built. |
| `-v ~/theDebs:/debs` | Mounts a local folder ($HOME/theDebs) to store the finished packages. |

Some environment variables can be added to the "docker run" command with the "-e variable=value" syntax:

| Variable name | Purpose |
| CORES | Integer; sets the number of cores used to compile packages. The default value is half the available cpu cores. |
| http_proxy,<br>https_proxy | http\[s\]://ProxyAddress:PORT standard form |
| SUPPRESSAMD | Default is "false", may be set "true", to control building of packages for AMD/x86_64 |
| SUPPRESSARM | Default is "false", may be set "true", to control building of packages for AMD/x86_64 |
| SUPPRESSKERNEL | Default is "false", may be set "true", to control building of just the kernel |

To completely remove the container:

```
docker stop l4fame-build
docker rm l4fame-build
docker rmi l4fame-build
```

To remove the source repos and build artifacts:

```
docker volume rm L4FAME_BUILD
```

### End Results

On completion ~/theDebs should contain all the packages necessary for running
code in a FAME environment, on a SuperDome Flex global memory environment,
or The Machine itself (ARM).

At the top level will be all the packages and a directory called "logs".
Under logs is one file per built package, making it easy to troubleshoot 
build problems.  There is also a file named "00_mainloop.log", a global catchall
for builder.bash flow.   These files are only created if builder.bash
was enabled for AMD (the default).

If you have enabled builder.bash for ARM (the default), you'll see a another directory
under theDebs, "arm64".  Under there is a similar structure: all the debs
plus a "log" directory with multiple files as described above.

## Building Individual Packages

Instructions for building individual packages can be found **[here](BuildRules.md)**

## External Links

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
