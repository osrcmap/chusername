# syntax=docker/dockerfile:1

FROM archlinux:latest

RUN pacman -Syu --noconfirm && pacman -S --noconfirm vim sudo

RUN useradd -m -s /bin/bash oskkk && \
usermod -aG wheel oskkk && \
echo -n testpass | passwd -s oskkk

RUN echo "oskkk:100000:65536" >> /etc/subuid && \
    echo "oskkk:100000:65536" >> /etc/subgid

COPY chusername.sh /chusername.sh
RUN chmod +x /chusername.sh

CMD ["bash"]
