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


## Launching Docker Image

Once the Docker image has been built or downloaded it needs to be run with:

(depending on the method used to acquire the Docker image)

```
docker run --rm -v /builder:/home -v /home/deb:/deb l4fame-build-container

docker run --rm -v /builder:/home -v /home/deb:/deb austinhpe/l4fame-build-container

docker run --rm -v /builder:/home -v /home/deb:/deb austinhpe/l4fame-build-container-large
```
| Docker Flag | Explanation |
| ----------- | ----------- |
| --rm | Removes the container after completion to reduce disk usage |
| -v /builder:/home | Mounts a folder to hold packages and temporary files as they are being built |
| -v /home/deb:/deb | Mounts a folder to store the finished packages |


### End Results

On completion /home/deb should contain all the packages necessary for running code on The Machine.


## External Links

* [l4fame-build-container](https://hub.docker.com/r/austinhpe/l4fame-build-container/) - Dockerhub image for the build container
* [l4fame-build-container-large](https://hub.docker.com/r/austinhpe/l4fame-build-container-large/) - Dockerhub image for the large build container
* [debserve](https://hub.docker.com/r/davidpatawaran/debserve/) - Dockerhub image for debserve

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
