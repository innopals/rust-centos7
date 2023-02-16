ARG SHA
FROM centos@sha256:$SHA
ARG RUST_VERSION
WORKDIR /root
RUN uname -m && yum install -y gcc-c++ make vim curl wget epel-release && \
    yum install -y cmake3 && ln -s /usr/bin/cmake3 /usr/bin/cmake && \
    yum clean all -y
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain $RUST_VERSION
ENV PATH=/root/.cargo/bin:$PATH
