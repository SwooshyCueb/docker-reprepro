FROM ubuntu:focal as reprepro_base

SHELL [ "/bin/bash", "-c" ]

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# Fix a thing in the ubuntu image
RUN apt-get update && \
    apt-get install -y --no-install-recommends apt-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# upgrade, autoremove, mark manual
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get autoremove -y --purge && \
    apt-mark showauto | xargs -r apt-mark manual && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# install gnupg1
RUN apt-get update && \
    apt-get install -y --no-install-recommends gnupg && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# add nginx repo
RUN echo "deb http://ppa.launchpad.net/ondrej/nginx-mainline/ubuntu focal main" \
        >> /etc/apt/sources.list.d/nginx.list \
    && \
    apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys \
        14AA40EC0831756756D7F66C4F4EA0AAE5267A6C \
        30B933D80FCE3D981A2D38FB0C99B70EF4FCBB07 \
        6A1AAD7AE5B401C6E259A7B257067BAA1314C7FC \
    && \
    rm -rf /var/lib/apt/lists/* /tmp/*

# One more upgrade+autoremove
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get autoremove -y --purge -o APT::Autoremove::RecommendsImportant=0 -o APT::Autoremove::SuggestsImportant=0 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        curl \
    && \
    apt-get install -y \
        reprepro \
        nginx-light \
        libnginx-mod-http-fancyindex \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/*

ENV REPREPRO_DEFAULT_NAME=Reprepro \
    REPREPRO_BASE_DIR_NAME=ubuntu

# Configure an reprepro user (admin)
RUN adduser --system --group --shell /bin/bash --uid 600 --disabled-password --no-create-home reprepro

# Configure an apt user (read only)
#RUN adduser --system --group --shell /bin/bash --uid 601 --disabled-password --no-create-home apt

RUN mkdir /var/run/sshd
ADD sshd_config.in /sshd_config.in

RUN rm -f /etc/nginx/nginx.conf
ADD nginx.conf /etc/nginx/nginx.conf

ADD run.sh /run.sh
RUN chmod +x /run.sh

VOLUME ["/config"]
VOLUME ["/data"]

# sshd
EXPOSE 22

# nginx
EXPOSE 80

CMD ["/run.sh"]
