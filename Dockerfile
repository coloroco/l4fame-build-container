FROM debian:stretch

LABEL maintainer="Austin Hunting"
LABEL maintainer_email="austin.hunting@hpe.com"

ENV DEBIAN_FRONTEND=noninteractive
RUN touch .in_docker_container
RUN apt-get update && apt-get -y install git


# TODO: Added cp builder to satisfy using basename $0 over $0
# TODO: Will remove in favor of other method
CMD git clone https://github.com/AustinHunting/l4fame-build-container.git; \
    ( cd l4fame-build-container && git stash && git pull ); \
    ( cp /l4fame-build-container/builder.bash / && bash /builder.bash );

