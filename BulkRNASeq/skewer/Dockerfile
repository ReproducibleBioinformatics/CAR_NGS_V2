FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y r-base-core \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY skewer-0.2.2-linux-x86_64 /usr/local/bin/skewer
RUN chmod +x /usr/local/bin/skewer

COPY check_samplemetadata.R /usr/local/bin/check_samplemetadata.R
RUN chmod +x /usr/local/bin/check_samplemetadata.R

COPY start.sh /home
RUN chmod +x /home/start.sh

WORKDIR /home
CMD ["bash"]