# syntax=docker/dockerfile:1

FROM fedora:latest

RUN dnf install -y vim sudo shadow-utils

RUN useradd -m -s /bin/bash oskkk && \
usermod -aG wheel oskkk && \
echo "oskkk:testpass" | chpasswd

RUN echo "oskkk:100000:65536" >> /etc/subuid && \
    echo "oskkk:100000:65536" >> /etc/subgid

COPY chusername.sh /chusername.sh
RUN chmod +x /chusername.sh

CMD ["bash"]
