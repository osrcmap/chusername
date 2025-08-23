# syntax=docker/dockerfile:1

FROM debian:latest

RUN apt-get update && apt-get install -y vim sudo

RUN apt-get update && apt-get install -y vim sudo; \
useradd -m -s /bin/bash oskkk && \
usermod -aG sudo oskkk && \
echo -n testpass | passwd -s oskkk

CMD ["bash"]
