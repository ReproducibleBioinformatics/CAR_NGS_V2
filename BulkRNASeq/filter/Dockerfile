FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
    r-base \
    r-cran-data.table \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY filter.R /usr/local/bin/filter.R
RUN chmod +x /usr/local/bin/filter.R

COPY start.sh /home/start.sh
RUN chmod +x /home/start.sh

WORKDIR /home

CMD ["bash"]