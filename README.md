# L4fame Build Container

This repository contains a bash script and Dockerfile that will pull and build the Fabric Attached Memory packages necessary for running code on The Machine.

### Known Working Environments
This build container has been tested and verified working on the following operating systems :
- Red Hat Enterprise Linux 7.3
- Ubuntu 17.04
- Fedora 26
- Debian Jessie

## Getting Started

This repository can be cloned and built, or a complete image can be downloaded off Dockerhub.

### Clone & Build

Clone and build the repository with:

```
git clone git@github.com:FabricAttachedMemory/l4fame-build-container.git
cd l4fame-build-container && docker build -t l4fame-build-container .
```

### Pull from Dockerhub

Pull the prebuilt image from Dockerhub.

```
docker pull austinhpe/l4fame-build-container
```


## Launching the Docker Image

Once the Docker image has been built or downloaded it needs to be run with:

(depending on the method used to acquire the Docker image)

```
docker run -t --name l4fame-builder --privileged -v BUILD:/build -v ~/deb:/deb l4fame-build-container

docker run -t --name l4fame-builder --privileged -v BUILD:/build -v ~/deb:/deb austinhpe/l4fame-build-container
```

To disconnect from the container without killing it run `Ctrl+C`

To reconnect to the container run `docker attach l4fame-builder`


| Docker Flag | Explanation |
| ----------- | ----------- |
| `-t` | Allocates and attaches a pseudo-tty, this allows us to background the container without killing it. |
| `--name l4fame-builder` | Names the container "l4fame-builder" to simplify subsequent runs. |
| `--privileged` | Gives the container enough privileges to enter a chroot and build arm64 packages. |
| `-v BUILD:/build` | Creates a new Docker volume named BUILD to hold packages and temporary files as they are being built. |
| `-v ~/deb:/deb` | Mounts a folder to store the finished packages. |
| `-e cores=number_of_cores` | **Optional Flag** Sets the number of cores used to compile packages. Replace `number_of_cores` with an integer value. If this flag is left off the container will automatically use half the available cpu cores capped at 8. |
| `-e http_proxy=http://ProxyAddress:PORT`<br>`-e https_proxy=https://ProxyAddress:PORT` | **Optional Flag** Sets the containers `http_proxy` and `https_proxy` variables. This flag needs to be set when this container is running on a machine that requires a proxy to reach the internet. |


### End Results

On completion ~/deb should contain all the packages necessary for running code on The Machine.


## Building Individual Packages

Instructions for building individual packages can be found **[here](BuildRules.md)**


## External Links

* [l4fame-build-container](https://hub.docker.com/r/austinhpe/l4fame-build-container/) - Dockerhub image for the build container
* [debserve](https://hub.docker.com/r/davidpatawaran/debserve/) - Dockerhub image for debserve

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
