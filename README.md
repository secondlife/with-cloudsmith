# with-cloudsmith

**with-cloudsmith** is a CLI tool for temporarily injecting Cloudsmith package
source configurations into an environment. This can be useful when you want
to consume private packages as part of a Dockerfile build but do not want to
leave credentials behind in the resulting image.

Supported registry types:

- Debian
- Pip (Python)

## Use

```text
Usage: with-cloudsmith [options] [--] command

  Set up private Cloudsmith registries temporarily.

Options:
  -r, --repo <repo>       Cloudsmith repository name
  -o, --org <org>         Cloudsmith organization name
  -v, --verbose           Enable verbose output
  -vv                     Enable debug output
  -s, --silent            Silence output
  --pip                   Enable PIP registry
  --deb                   Enable Debian registry
  -k, --keep              Keep temporary files
  -h, --help              Show this help message
```

First, add **with-cloudsmith** to your Dockerfile:
```dockerfile
FROM debian:bookworm-slim

ADD https://raw.githubusercontent.com/secondlife/with-cloudsmith/v0.1.0/with-cloudsmith /usr/bin/
```

## Debian

To install debian packages from a private Cloudsmith repository:
```dockerfile
# Install cloudsmith apt source dependencies
RUN apt-get update \
    && apt-get install -y apt-transport-https ca-certificates curl gnupg \
    && rm -rf /var/lib/apt/lists/*

# Install private dependencies
RUN --mount=type=secret,id=CLOUDSMITH_API_KEY \
    with-cloudsmith -v --repo REPO --org ORG --deb \
    apt-get install -y PACKAGE \
    && rm -rf /var/lib/apt/lists/*
```

Then, assuming you have the environment variable CLOUDSMITH_API_KEY available, build the image:
```
$ docker build --secret id=CLOUDSMITH_API_KEY local/example .
```

## Pip

Private python packages can be installed using **with-cloudsmith** like so:

```dockerfile
RUN --mount=type=secret,id=CLOUDSMITH_API_KEY \
    with-cloudsmith --repo REPO --org ORG --pip pip install ...
```

Build the image the same as before, passing a build `--secret`.

## Credentials

**with-cloudsmith** desperately searches the following locations for credentials:

- Environment variables: `CLOUDSMITH_API_KEY`, `CLOUDSMITH_TOKEN`, `CLOUDSMITH_USER`, `CLOUDSMITH_PASSWORD`
- Ini files: `$HOME/.cloudsmith/credentials.ini`, `$HOME/.config/credentials.ini`, `$PWD/credentials.ini`
- Docker build secrets: `/run/secrets/CLOUDSMITH_API_KEY`, et al.
- `/run/secrets/cloudsmith`: A special file that can either be your cloudsmith-cli credentials.ini or a source-able dotenv.

## Tips and tricks

Let's say you want to inspect private packages for awhile, perhaps to query
and search dependencies. You have two options:

```sh
# Keep the private sources around:
with-cloudsmith --keep ...

# Create a subshell:
with-cloudsmith bash
```
