FROM debian:latest

LABEL maintainer="Rocky Craig"
LABEL maintainer_email="rocky.craig@hpe.com"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get -y install git

# WORKDIR is /
COPY builder.bash /builder.bash

CMD /builder.bash
