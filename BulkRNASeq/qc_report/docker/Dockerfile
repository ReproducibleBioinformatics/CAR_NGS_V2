FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC
#
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    fontconfig \
    fonts-dejavu-core \
    libharfbuzz0b \
    openjdk-21-jre-headless \
    perl \
    python3 \
    python3-pip \
    r-base \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN pip3 install multiqc --break-system-packages

COPY FastQC/ /usr/local/bin/FastQC/
RUN chmod +x /usr/local/bin/FastQC/fastqc
ENV PATH="/usr/local/bin/FastQC:${PATH}"

COPY check_samplemetadata.R /usr/local/bin/check_samplemetadata.R
RUN chmod +x /usr/local/bin/check_samplemetadata.R

COPY start.sh /home
RUN chmod +x /home/start.sh

WORKDIR /home
CMD ["bash"]