FROM debian:stretch

LABEL maintainer="Austin Hunting"
LABEL maintainer_email="austin.hunting@hpe.com"

ENV DEBIAN_FRONTEND=noninteractive
RUN touch .in_docker_container
RUN apt-get update && apt-get -y install git

# WORKDIR is /
COPY builder.bash /builder.bash
CMD /builder.bash