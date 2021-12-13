#! /bin/sh

/kaniko/executor --context=dir:///src --dockerfile=Dockerfile --destination=registry.kube-system:80/target --insecure --skip-tls-verify --skip-tls-verify-pull --insecure-pull
/bin/sleep 10
