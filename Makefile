DOCKER ?= docker
IMAGE ?= php81-rpm-el7:local
RELEASE ?= 7
JOBS ?= 2
PAGES_BASE_URL ?=
REPO_DIR ?= dist/repo/el7/x86_64

# RPM -> tests -> signing -> metadata -> Pages must remain ordered with make -j.
.NOTPARALLEL:

.PHONY: all image rpm smoke repo pages sign-rpms sign-repo signed-repo check
all: rpm smoke repo

image:
	$(DOCKER) build --build-arg BUILD_UID="$$(id -u)" --build-arg BUILD_GID="$$(id -g)" \
		-f docker/Dockerfile.el7 -t $(IMAGE) .

rpm: image
	$(DOCKER) run --rm --user "$$(id -u):$$(id -g)" \
		-v "$$(pwd):/work" -w /work -e PHP_RELEASE=$(RELEASE) -e BUILD_JOBS=$(JOBS) \
		$(IMAGE) ./scripts/build-rpm.sh

smoke:
	$(DOCKER) run --rm -v "$$(pwd):/work:ro" -w /work -e PHP_RELEASE=$(RELEASE) $(IMAGE) ./scripts/smoke-test-rpm.sh

repo:
	$(DOCKER) run --rm --user "$$(id -u):$$(id -g)" \
		-v "$$(pwd):/work" -w /work $(IMAGE) ./scripts/create-repo.sh

pages:
	PAGES_BASE_URL="$(PAGES_BASE_URL)" REPO_DIR="$(REPO_DIR)" ./scripts/build-pages.sh

sign-rpms sign-repo:
	$(DOCKER) run --rm --user "$$(id -u):$$(id -g)" \
		-v "$$(pwd):/work" -w /work -e RPM_GPG_NAME -e RPM_GPG_PRIVATE_KEY_B64 \
		-e RPM_GPG_PRIVATE_KEY_FILE -e RPM_GPG_PUBLIC_KEY_OUT \
		$(IMAGE) ./scripts/$@.sh

signed-repo: rpm smoke sign-rpms repo sign-repo pages

check:
	@for script in scripts/*.sh; do bash -n "$$script" || exit; done
	git diff --check
