FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PATH="/usr/local/bin/cellranger-10.1.0:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    ca-certificates \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

COPY cellranger-10.1.0.tar /usr/local/bin/
RUN tar -xzf /usr/local/bin/cellranger-10.1.0.tar -C /usr/local/bin/ \
    && rm -f /usr/local/bin/cellranger-10.1.0.tar

COPY start.sh /home/start.sh
RUN chmod +x /home/start.sh

CMD ["/bin/bash"]