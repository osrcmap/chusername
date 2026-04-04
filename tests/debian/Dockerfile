# syntax=docker/dockerfile:1

FROM debian:latest

RUN apt-get update && apt-get install -y vim sudo

RUN useradd -m -s /bin/bash oskkk && \
usermod -aG sudo oskkk && \
echo -n testpass | passwd -s oskkk

RUN echo "oskkk:100000:65536" >> /etc/subuid && \
    echo "oskkk:100000:65536" >> /etc/subgid

COPY chusername.sh /chusername.sh
RUN chmod +x /chusername.sh

CMD ["bash"]
