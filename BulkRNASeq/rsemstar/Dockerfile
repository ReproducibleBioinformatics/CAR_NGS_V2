FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base \
    perl \
    build-essential \
    zlib1g-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*    

COPY RSEM-1.3.3 /usr/local/bin/RSEM-1.3.3
RUN chmod -R 755 /usr/local/bin/RSEM-1.3.3
RUN cd /usr/local/bin/RSEM-1.3.3 && make
ENV PATH="/usr/local/bin/RSEM-1.3.3:${PATH}"

ADD 2.7.11b.tar.gz /home/
RUN mkdir -p /usr/local/bin \
    && cp /home/STAR-2.7.11b/bin/Linux_x86_64_static/STAR /usr/local/bin/STAR \
    && chmod +x /usr/local/bin/STAR \
    && rm -rf /home/STAR-2.7.11b

COPY check_samplemetadata.R /usr/local/bin/check_samplemetadata.R
RUN chmod +x /usr/local/bin/check_samplemetadata.R

COPY start.sh /home/start.sh
RUN chmod +x /home/start.sh

WORKDIR /home

CMD ["bash"]