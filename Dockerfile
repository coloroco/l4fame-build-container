FROM debian:stretch
# TODO: From his
#FROM debian:latest

LABEL maintainer="Austin Hunting"
LABEL maintainer_email="austin.hunting@hpe.com"

ENV DEBIAN_FRONTEND=noninteractive
RUN touch .in_docker_container
RUN apt-get update && apt-get -y install git

# TODO: From mine
#CMD git clone https://github.com/FabricAttachedMemory/l4fame-build-container.git; \
#    ( cd l4fame-build-container && git stash && git pull ); \
#    ( cd l4fame-build-container && bash builder.bash );

# WORKDIR is /
COPY builder.bash /builder.bash
CMD /builder.bash