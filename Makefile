# Copyright 2018 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Bump these on release
VERSION_MAJOR ?= 1
VERSION_MINOR ?= 7
VERSION_BUILD ?= 0

VERSION ?= v$(VERSION_MAJOR).$(VERSION_MINOR).$(VERSION_BUILD)
VERSION_PACKAGE = $(REPOPATH/pkg/version)

SHELL := /bin/bash
GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
ORG := github.com/GoogleContainerTools
PROJECT := kaniko
REGISTRY?=gcr.io/kaniko-project

REPOPATH ?= $(ORG)/$(PROJECT)
VERSION_PACKAGE = $(REPOPATH)/pkg/version

GO_FILES := $(shell find . -type f -name '*.go' -not -path "./vendor/*")
GO_LDFLAGS := '-extldflags "-static"
GO_LDFLAGS += -X $(VERSION_PACKAGE).version=$(VERSION)
GO_LDFLAGS += -w -s # Drop debugging symbols.
GO_LDFLAGS += '

EXECUTOR_PACKAGE = $(REPOPATH)/cmd/executor
WARMER_PACKAGE = $(REPOPATH)/cmd/warmer
KANIKO_PROJECT = $(REPOPATH)/kaniko
BUILD_ARG ?=

# Force using Go Modules and always read the dependencies from
# the `vendor` folder.
export GO111MODULE = on
export GOFLAGS = -mod=vendor


out/executor: $(GO_FILES)
	GOARCH=$(GOARCH) GOOS=linux CGO_ENABLED=0 go build -ldflags $(GO_LDFLAGS) -o $@ $(EXECUTOR_PACKAGE)

out/warmer: $(GO_FILES)
	GOARCH=$(GOARCH) GOOS=linux CGO_ENABLED=0 go build -ldflags $(GO_LDFLAGS) -o $@ $(WARMER_PACKAGE)

.PHONY: install-container-diff
install-container-diff:
	@ curl -LO https://github.com/GoogleContainerTools/container-diff/releases/download/v0.17.0/container-diff-linux-amd64 && \
		chmod +x container-diff-linux-amd64 && sudo mv container-diff-linux-amd64 /usr/local/bin/container-diff

.PHONY: minikube-setup
minikube-setup:
	@ ./scripts/minikube-setup.sh

.PHONY: test
test: out/executor
	@ ./scripts/test.sh

.PHONY: integration-test
integration-test:
	@ ./scripts/integration-test.sh

.PHONY: integration-test-run
integration-test-run:
	@ ./scripts/integration-test.sh -run "TestRun"

.PHONY: integration-test-layers
integration-test-layers:
	@ ./scripts/integration-test.sh -run "TestLayers"

.PHONY: integration-test-k8s
integration-test-k8s:
	@ ./scripts/integration-test.sh -run "TestK8s"

.PHONY: integration-test-misc
integration-test-misc:
	$(eval RUN_ARG=$(shell ./scripts/misc-integration-test.sh))
	@ ./scripts/integration-test.sh -run "$(RUN_ARG)"

.PHONY: k8s-executor-build-push
k8s-executor-build-push:
	DOCKER_BUILDKIT=1 docker build ${BUILD_ARG} --build-arg=GOARCH=$(GOARCH) -t $(REGISTRY)/executor:latest -f deploy/Dockerfile .
	docker push $(REGISTRY)/executor:latest

.PHONY: images
images:
	docker build ${BUILD_ARG} --build-arg=GOARCH=$(GOARCH) -t $(REGISTRY)/executor:latest -f deploy/Dockerfile .
	docker build ${BUILD_ARG} --build-arg=GOARCH=$(GOARCH) -t $(REGISTRY)/executor:debug -f deploy/Dockerfile_debug .
	docker build ${BUILD_ARG} --build-arg=GOARCH=$(GOARCH) -t $(REGISTRY)/executor:slim -f deploy/Dockerfile_slim .
	docker build ${BUILD_ARG} --build-arg=GOARCH=$(GOARCH) -t $(REGISTRY)/warmer:latest -f deploy/Dockerfile_warmer .

.PHONY: push
push:
	docker push $(REGISTRY)/executor:latest
	docker push $(REGISTRY)/executor:debug
	docker push $(REGISTRY)/executor:slim
	docker push $(REGISTRY)/warmer:latest

setup-local-dev:
	@tput bold
	@tput setaf 1
	echo "Make sure to have run this in another terminal: 'minikube start && minikube dashboard'"
	@echo
	@tput sgr0
	minikube addons enable registry
	minikube addons enable registry-aliases
	kubectl apply -f local-dev/minikube-registry.yaml
	# kubectl rollout restart -n kube-system daemonset registry-aliases-hosts-update
	- kubectl create --save-config namespace efk
	- kubectl create --save-config namespace kaniko
	kubectl apply -n efk -f https://github.com/srfrnk/efk-stack-helm/releases/latest/download/efk-manifests.yaml
	kubectl wait -n efk --for=condition=complete --timeout=600s job/initializer
	@tput bold
	@tput setaf 2
	@echo
	@echo "You can view Kibana in your browser by going to http://localhost:5601/app/discover"
	@echo
	@tput sgr0
	kubectl port-forward -n efk svc/efk-kibana 5601

update-local-dev:
	build_number=$(eval BUILD_NUMBER=$(shell od -An -N10 -i /dev/urandom | tr -d ' -' ))

	curl -L -o ./local-dev/busybox.tar.xz https://github.com/docker-library/busybox/raw/50b2c75ecc4c23c4ec47f3a4a0a2fd82002a1a33/stable/uclibc/busybox.tar.xz

	eval $$(minikube docker-env) && docker build ${BUILD_ARG} --build-arg=GOARCH=$(GOARCH) -t executor:${BUILD_NUMBER} -f deploy/Dockerfile .
	eval $$(minikube docker-env) && docker build --build-arg "IMAGE_VERSION=:${BUILD_NUMBER}" -t kaniko-runner:${BUILD_NUMBER} -f local-dev/kaniko-runner.Dockerfile local-dev

	- kubectl delete job -n kaniko --all
	kubectl apply -f local-dev/network-policy.yaml
	yq e ".spec.template.spec.containers[0].image=\"kaniko-runner:${BUILD_NUMBER}\"" local-dev/job.yaml | kubectl apply -f -
