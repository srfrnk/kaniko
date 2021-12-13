ARG IMAGE_VERSION

FROM golang:1.15 as golang

FROM executor${IMAGE_VERSION} as kaniko

ADD busybox.tar.xz /

COPY kaniko-runner.sh /kaniko-runner.sh
COPY run_in_container.sh /src/run_in_container.sh
COPY target.Dockerfile /src/Dockerfile

ENTRYPOINT ["/bin/sh","-c"]
CMD ["/kaniko-runner.sh"]
