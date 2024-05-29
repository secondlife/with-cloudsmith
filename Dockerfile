FROM debian:bookworm-slim

COPY ./with-cloudsmith /usr/bin/

RUN apt-get update \
    && apt-get install -y apt-transport-https ca-certificates curl gnupg \
