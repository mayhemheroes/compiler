# Build Stage
FROM --platform=linux/amd64 ubuntu:20.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y vim less man wget tar git gzip unzip make cmake software-properties-common curl 
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y gcc gcc-multilib

ADD . /compiler
WORKDIR /compiler/build
RUN cmake ../source/compiler -DCMAKE_C_FLAGS=-m32 -DCMAKE_BUILD_TYPE=Release
RUN make -j8
