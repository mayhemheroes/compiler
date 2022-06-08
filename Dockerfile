FROM --platform=linux/amd64 ubuntu:20.04 as builder
RUN apt-get update
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y gcc gcc-multilib cmake make

ADD . /compiler
WORKDIR /compiler/build
RUN cmake ../source/compiler -DCMAKE_C_FLAGS=-m32 -DCMAKE_BUILD_TYPE=Release
RUN make -j8

RUN mkdir -p /deps
RUN ldd /compiler/build/pawncc | tr -s '[:blank:]' '\n' | grep '^/' | xargs -I % sh -c 'cp % /deps;'

FROM ubuntu:20.04 as package

COPY --from=builder /deps /deps
COPY --from=builder /compiler/build/pawncc /compiler/build/pawncc
ENV LD_LIBRARY_PATH=/deps
