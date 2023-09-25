FROM ubuntu:22.04

LABEL org.opencontainers.image.authors="René Schubotz"
LABEL org.opencontainers.image.source="https://github.com/rmrschub/aetna-jupyterlab/"

# Hide CUDA devices: this  provides an IDE and expects GPU workloads to be scheduled to GPU nodes
ENV CUDA_VISIBLE_DEVICES=""
ENV NVIDIA_VISIBLE_DEVICE=""

# User setup
ARG NB_USER
ARG NB_GROUP
ARG NB_UID
ARG NB_PREFIX
ARG HOME

ENV NB_USER ${NB_USER:-jovyan}
ENV NB_GROUP ${NB_GROUP:-users}
ENV NB_UID ${NB_UID:-1000}
ENV NB_PREFIX ${NB_PREFIX:-/}
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME 0
ENV HOME /home/$NB_USER
ENV SHELL /bin/bash

# Set shell to bash
SHELL ["/bin/bash", "-c"]

# Install linux packages from packages.txt
COPY packages.txt /tmp/packages.txt
RUN apt update -yq && \
    apt install -yq --no-install-recommends $(cat /tmp/packages.txt) && \
    rm -f /tmp/packages.txt; \
    rm -rf /var/lib/apt/lists 

# Install Github CLI
RUN type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y); \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && sudo apt update \
    && sudo apt install gh -y

# Create user and set required ownership
RUN useradd -M -s "$SHELL" -N -u ${NB_UID} ${NB_USER}; \
    if [[ -n "$HOME" && ! -d "$HOME" ]]; then \
        mkdir -p "${HOME}"; \
        chown "$NB_USER:$NB_GROUP" -R "$HOME"; \
    fi; \
    if [[ ! -f /etc/sudoers ]] || ! grep -q "^${NB_USER}[[:space:]]" /etc/sudoers; then \
        if [[ ! -f /etc/sudoers ]]; then \
            touch /etc/sudoers; \
        fi; \
        chmod 0660 /etc/sudoers; \
        echo "${NB_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers; \
        chmod 0440 /etc/sudoers; \
    fi;

# set locale configs
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
 && locale-gen
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV LC_ALL en_US.UTF-8

# Install and validate latest kubectl
RUN set -x; \
    curl -sL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" -o /usr/local/bin/kubectl; \
    curl -sL "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256" -o /tmp/kubectl.sha256; \
    echo "$(cat /tmp/kubectl.sha256) /usr/local/bin/kubectl" | sha256sum --check; \
    rm /tmp/kubectl.sha256; \
    chmod +x /usr/local/bin/kubectl; 

# Install python packages from requirements.txt
ENV DEBIAN_FRONTEND="noninteractive" 
ENV TZ="Europe/Berlin"
RUN set -ex; \
    \
    apt update \
    && apt upgrade -y ;\
    apt-get install -y software-properties-common;\
    add-apt-repository ppa:deadsnakes/ppa -y; \
    apt update; \
    apt install -y python3.10-full; \
    apt install -y python3-pip; \
    python3 -m pip install --upgrade pip; \
    pip --version;

COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt; \
    rm -f /tmp/requirements.txt;  

# Set default user
USER $NB_USER

CMD [ "start-notebook.sh", "--no-browser", "--ip=0.0.0.0", ]