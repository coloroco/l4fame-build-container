# L4fame Build Container

This repository contains a bash script and Dockerfile that will pull and build the Fabric Attached Memory packages necessary for running code on The Machine.

### Known Working Environments
This build container has been tested and verified working on the following operating systems :
- Red Hat Enterprise Linux 7.3
- Ubuntu 17.04
- Fedora 26
- Debian Jessie

## Getting Started

This repository can be cloned and built locally OR a complete image can be downloaded off Dockerhub.

### Set up your firewall proxies

If you are behind a corporate firewall, Docker needs to know.
[This article](https://elegantinfrastructure.com/docker/ultimate-guide-to-docker-http-proxy-configuration/)
explains it all.

### Clone & Build

Clone and build the repository with:

```
git clone git@github.com:FabricAttachedMemory/l4fame-build-container.git
cd l4fame-build-container && docker build --tag l4fame-build .
```

If you're behind a firewall and have the standard environment variables set,
add

```
--build-arg http_proxy=$http_proxy --build-arg https_proxy=$https_proxy
```
to the arguments.

## Launching the Docker container

Once the Docker image has been built or downloaded it needs to be run.
First create an empty directory in $HOME to hold the results:

```
mkdir $HOME/theDebs
```

Downloaded and built locally:
```
docker run -t --name l4fame-build --privileged -v ~/theDebs:/debs -v L4FAME_BUILD:/build ~/deb:/deb l4fame-build
```

To disconnect from the container without killing it run `Ctrl+C`

To reconnect to the container run `docker attach l4fame-builder`


| Docker Flag | Explanation |
| ----------- | ----------- |
| `-t` | Allocates and attaches a pseudo-tty, this allows the container to be killed (Ctrl-C) or sent to the background. |
| `--name l4fame-build` | Names the container "l4fame-build" to simplify subsequent runs. |
| `--privileged` | Gives the container enough privileges to enter a chroot and build arm64 packages. |
| `-v L4FAME_BUILD:/build` | Creates a new Docker volume named L4FAME_BUILD to hold packages and temporary files as they are being built. |
| `-v ~/theDebs:/debs` | Mounts a local folder ($HOME/theDebs) to store the finished packages. |
| `-e cores=number_of_cores` | **Optional Flag** Sets the number of cores used to compile packages. Replace `number_of_cores` with an integer value. If this flag is left off the container will automatically use half the available cpu cores capped at 8. |
| `-e http_proxy=http://ProxyAddress:PORT`<br>`-e https_proxy=https://ProxyAddress:PORT` | **Optional Flag** Sets `http_proxy` and `https_proxy` environment variables inside the container. These flags are only needed if your host system is behind a firewall. |


### End Results


On completion ~/theDebs should contain all the packages necessary for running
code in a FAME environment, on a SuperDome Flex global memory environment,
or The Machine itself (ARM).

At the top level will be all the packages and a directory called "logs".
Under logs is one file per built package, making it easy to troubleshoot 
build problems.  There is also a file named "1stlog", a global catchall
for builder.bash flow.   These files are only created if builder.bash
was enabled for AMD, ie, suppressamd=false.

If you have enabled builder.bash for ARM, you'll see a another directory
under theDebs, "arm64".  Under there is a similar structure: all the debs
plus a "log" directory with multiple files as described above.


## Building Individual Packages

Instructions for building individual packages can be found **[here](BuildRules.md)**

## External Links

* [l4fame-build-container](https://hub.docker.com/r/austinhpe/l4fame-build-container/) - Dockerhub image for the build container
* [debserve](https://hub.docker.com/r/davidpatawaran/debserve/) - Dockerhub image for debserve

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
