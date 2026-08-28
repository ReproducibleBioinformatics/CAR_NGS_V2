FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    rpm \
    locales \
    zlib1g \
    liblzma5 \
    libbz2-1.0 \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

COPY bcl2fastq2-v2.20.0.422-Linux-x86_64.rpm /tmp/bcl2fastq.rpm
RUN rpm -i --nodeps /tmp/bcl2fastq.rpm \
    && rm -f /tmp/bcl2fastq.rpm \
    && apt-get purge -y --auto-remove rpm \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/local/bin:${PATH}"

COPY start.sh /home/start.sh
RUN chmod +x /home/start.sh

CMD ["/bin/bash"]