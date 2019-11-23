ROOT :=  $(shell pwd)
COVERAGE_OUTPUT_PATH := ${ROOT}/cover.out
LICENSES_PATH := ${ROOT}/licenses

# Image URL to use all building/pushing image targets
UPLOADER_IMG_NAME ?= rafter-upload-service
MANAGER_IMG_NAME ?= rafter-controller-manager
FRONT_MATTER_IMG_NAME ?= rafter-front-matter-service
ASYNCAPI_IMG_NAME ?= rafter-asyncapi-service

IMG-CI-NAME-PREFIX := $(DOCKER_PUSH_REPOSITORY)$(DOCKER_PUSH_DIRECTORY)

UPLOADER-CI-IMG-NAME := $(IMG-CI-NAME-PREFIX)/$(UPLOADER_IMG_NAME):$(DOCKER_TAG)
UPLOADER-CI-IMG-NAME-LATEST := $(IMG-CI-NAME-PREFIX)/$(UPLOADER_IMG_NAME):latest
MANAGER-CI-IMG-NAME :=  $(IMG-CI-NAME-PREFIX)/$(MANAGER_IMG_NAME):$(DOCKER_TAG)
MANAGER-CI-IMG-NAME-LATEST :=  $(IMG-CI-NAME-PREFIX)/$(MANAGER_IMG_NAME):latest
FRONTMATTER-CI-IMG-NAME := $(IMG-CI-NAME-PREFIX)/$(FRONT_MATTER_IMG_NAME):$(DOCKER_TAG)
FRONTMATTER-CI-IMG-NAME-LATEST := $(IMG-CI-NAME-PREFIX)/$(FRONT_MATTER_IMG_NAME):latest
ASYNCAPI-CI-IMG-NAME :=  $(IMG-CI-NAME-PREFIX)/$(ASYNCAPI_IMG_NAME):$(DOCKER_TAG)
ASYNCAPI-CI-IMG-NAME-LATEST :=  $(IMG-CI-NAME-PREFIX)/$(ASYNCAPI_IMG_NAME):latest

# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

all: docker-build

build-uploader:
	docker build -t $(UPLOADER_IMG_NAME) -f ${ROOT}/deploy/uploader/Dockerfile ${ROOT}

push-uploader:
	docker tag $(UPLOADER_IMG_NAME) $(UPLOADER-CI-IMG-NAME)
	docker push $(UPLOADER-CI-IMG-NAME)

push-uploader-latest:
	docker tag $(UPLOADER_IMG_NAME) $(UPLOADER-CI-IMG-NAME-LATEST)
	docker push $(UPLOADER-CI-IMG-NAME-LATEST)

build-manager:
	docker build -t $(MANAGER_IMG_NAME) -f ${ROOT}/deploy/manager/Dockerfile ${ROOT}

push-manager:
	docker tag $(MANAGER_IMG_NAME) $(MANAGER-CI-IMG-NAME)
	docker push $(MANAGER-CI-IMG-NAME)

push-manager-latest:
	docker tag $(MANAGER_IMG_NAME) $(MANAGER-CI-IMG-NAME-LATEST)
	docker push $(MANAGER-CI-IMG-NAME-LATEST)

build-frontmatter:
	docker build -t $(FRONT_MATTER_IMG_NAME) -f ${ROOT}/deploy/extension/frontmatter/Dockerfile ${ROOT}

push-frontmatter:
	docker tag $(FRONT_MATTER_IMG_NAME) $(FRONTMATTER-CI-IMG-NAME)
	docker push $(FRONTMATTER-CI-IMG-NAME)

push-frontmatter-latest:
	docker tag $(FRONT_MATTER_IMG_NAME) $(FRONTMATTER-CI-IMG-NAME-LATEST)
	docker push $(FRONTMATTER-CI-IMG-NAME-LATEST)

build-asyncapi:
	docker build -t $(ASYNCAPI_IMG_NAME) -f ${ROOT}/deploy/extension/asyncapi/Dockerfile ${ROOT}

push-asyncapi:
	docker tag $(ASYNCAPI_IMG_NAME) $(ASYNCAPI-CI-IMG-NAME)
	docker push $(ASYNCAPI-CI-IMG-NAME)

push-asyncapi-latest:
	docker tag $(ASYNCAPI_IMG_NAME) $(ASYNCAPI-CI-IMG-NAME-LATEST)
	docker push $(ASYNCAPI-CI-IMG-NAME-LATEST)

clean:
	rm -f ${COVERAGE_OUTPUT_PATH}
	rm -rf ${LICENSES_PATH}

pull-licenses:
ifdef LICENSE_PULLER_PATH
	bash $(LICENSE_PULLER_PATH)
else
	mkdir -p ${LICENSES_PATH}
endif

fmt:
	find ${ROOT} -type f -name "*.go" \
	| egrep -v '_*/automock|_*/testdata|_*export_test.go' \
	| xargs -L1 go fmt

vet:
	@go list ${ROOT}/... \
	| grep -v "automock" \
	| xargs -L1 go vet

# Run tests
# Default is 20s - available since controller-runtime 0.1.5
test: export KUBEBUILDER_CONTROLPLANE_START_TIMEOUT = 2m
# Default is 20s - available since controller-runtime 0.1.5
test: export KUBEBUILDER_CONTROLPLANE_STOP_TIMEOUT = 2m
test: clean manifests vet fmt
	go test -short -coverprofile=${COVERAGE_OUTPUT_PATH} ${ROOT}/...
	@go tool cover -func=${COVERAGE_OUTPUT_PATH} \
		| grep total \
		| awk '{print "Total test coverage: " $$3}'

# Generate manifests e.g. CRD, RBAC etc.
manifests: controller-gen
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="${ROOT}/..." \
		object:headerFile=${ROOT}/hack/boilerplate.go.txt \
		output:crd:artifacts:config=${ROOT}/config/crd/bases \
		output:rbac:artifacts:config=${ROOT}/config/rbac \
		output:webhook:artifacts:config=${ROOT}/config/webhook

docker-build: \
	test \
	pull-licenses \
	build-uploader \
	build-frontmatter \
	build-asyncapi \
	build-manager

# Push the docker image
docker-push: \
	push-uploader \
	push-frontmatter \
	push-asyncapi \
	push-manager

# find or download controller-gen
# download controller-gen if necessary
controller-gen:
ifeq (, $(shell which controller-gen))
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.2.0
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif

ci-pr: docker-build docker-push

ci-release-push-latest: \
		   push-uploader-latest \
		   push-manager-latest \
		   push-frontmatter-latest \
		   push-asyncapi-latest

ci-master: docker-build docker-push

ci-release: docker-build docker-push ci-release-push-latest

start-docker: 
	${ROOT}/hack/ci/start_docker.sh

integration-test: \
	start-docker \
	build-uploader \
	build-manager \
	build-frontmatter \
	build-asyncapi 
	${ROOT}/hack/ci/run-integration-tests.sh \
		${UPLOADER_IMG_NAME} \
		${MANAGER_IMG_NAME} \
		${FRONT_MATTER_IMG_NAME} \
		${ASYNCAPI_IMG_NAME}

.PHONY: all \
		build-uploader \
		push-uploader \
		build-manager \
		push-manager \
		build-frontmatter \
		push-frontmatter \
		build-asyncapi \
		push-asyncapi \
		clean \
		pull-licenses \
		vet \
		fmt \
		test \
		manifests \
		docker-build \
		docker-push \
		controller-gen \
		ci-pr \
		ci-master \
		ci-release \
		push-uploader-latest \
		push-manager-latest \
		push-frontmatter-latest \
		push-asyncapi-latest \
		start-docker