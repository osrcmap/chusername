# syntax=docker/dockerfile:1

FROM archlinux:latest

RUN pacman -Syu --noconfirm && pacman -S --noconfirm vim sudo

RUN useradd -m -s /bin/bash oskkk && \
usermod -aG wheel oskkk && \
echo -n testpass | passwd -s oskkk

CMD ["bash"]
