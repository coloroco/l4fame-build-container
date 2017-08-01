# L4fame Build Container

This repository contains a bash script and Dockerfile that will pull and build the Fabric Attached Memory packages necessary for running code on The Machine.

## Getting Started

This repository can be cloned and built, or a complete image can be downloaded off Dockerhub.

### Clone & Build

Clone and build the repository with:

```
git clone git@github.com:FabricAttachedMemory/l4fame-build-container.git
cd l4fame-build-container && docker build -t l4fame-build-container .
```

### Pull from Dockerhub

Pull the prebuilt image from Dockerhub. Two images are available:

```
docker pull austinhpe/l4fame-build-container
```

or (the large build container comes with all prerequisites already installed)

```
docker pull austinhpe/l4fame-build-container-large
```


## Launching the Docker Image

Once the Docker image has been built or downloaded it needs to be run with:

(depending on the method used to acquire the Docker image)

```
docker run -t --name l4fame-builder -v ~/builder:/home -v ~/deb:/deb l4fame-build-container

docker run -t --name l4fame-builder -v ~/builder:/home -v ~/deb:/deb austinhpe/l4fame-build-container

docker run -t --name l4fame-builder -v ~/builder:/home -v ~/deb:/deb austinhpe/l4fame-build-container-large
```
To disconnect from the container without killing it run `Ctrl+C`

To reconnect to the container run `docker attach l4fame-builder`

| Docker Flag | Explanation |
| ----------- | ----------- |
| -t | Allocate and attach a pseudo-tty, this allows us to background the container without killing it |
| --name l4fame-builder | Names the container "l4fame-builder" to simplify subsequent runs  |
| -v ~/builder:/home | Mounts a folder to hold packages and temporary files as they are being built |
| -v ~/deb:/deb | Mounts a folder to store the finished packages |


### End Results

On completion /home/deb should contain all the packages necessary for running code on The Machine.


## Building Individual Packages

Instructions for building individual packages can be found **[here](BuildRules.md)**


## External Links

* [l4fame-build-container](https://hub.docker.com/r/austinhpe/l4fame-build-container/) - Dockerhub image for the build container
* [l4fame-build-container-large](https://hub.docker.com/r/austinhpe/l4fame-build-container-large/) - Dockerhub image for the large build container
* [debserve](https://hub.docker.com/r/davidpatawaran/debserve/) - Dockerhub image for debserve

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
