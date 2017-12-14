FROM debian:latest

LABEL maintainer="Austin Hunting"
LABEL maintainer_email="austin.hunting@hpe.com"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get -y install git

COPY builder.bash builder.bash

CMD ./builder.bash
