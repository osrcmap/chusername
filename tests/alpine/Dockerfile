# syntax=docker/dockerfile:1

FROM alpine:latest

RUN apk add --no-cache bash shadow vim sudo

RUN useradd -m -s /bin/bash oskkk

RUN echo "oskkk:100000:65536" >> /etc/subuid && \
    echo "oskkk:100000:65536" >> /etc/subgid

COPY chusername.sh /chusername.sh
RUN chmod +x /chusername.sh

CMD ["bash"]
