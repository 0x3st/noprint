PYTHON ?= python3

.PHONY: bootstrap validate launch-dev list-ext dry-run-dev new-patch export-patch patch-list ci-verify-apply ci-verify-minimal

bootstrap:
	chmod +x scripts/bootstrap_local.sh scripts/build_chromium.sh scripts/new_patch.sh scripts/export_patch.sh scripts/ci_verify_chromium.sh launcher/antidetect.py
	./scripts/bootstrap_local.sh

validate:
	$(PYTHON) launcher/antidetect.py --global-config configs/global.json validate --profile dev

launch-dev:
	$(PYTHON) launcher/antidetect.py --global-config configs/global.json launch --profile dev

dry-run-dev:
	$(PYTHON) launcher/antidetect.py --global-config configs/global.json launch --profile dev --dry-run

list-ext:
	$(PYTHON) launcher/antidetect.py --global-config configs/global.json list-extensions

new-patch:
	@if [ -z "$(N)" ] || [ -z "$(SLUG)" ]; then \
	  echo "Usage: make new-patch N=0002 SLUG=load-antidetect-config-at-startup"; \
	  exit 1; \
	fi
	./scripts/new_patch.sh "$(N)" "$(SLUG)"

export-patch:
	@if [ -z "$(SRC)" ] || [ -z "$(COMMIT)" ] || [ -z "$(OUT)" ]; then \
	  echo "Usage: make export-patch SRC=.chromium/src COMMIT=HEAD OUT=0002-my-change.patch"; \
	  exit 1; \
	fi
	./scripts/export_patch.sh "$(SRC)" "$(COMMIT)" "$(OUT)"

patch-list:
	@find patches -maxdepth 1 -name "*.patch" | sort

ci-verify-apply:
	BUILD_MODE=apply-only ./scripts/ci_verify_chromium.sh

ci-verify-minimal:
	BUILD_MODE=minimal VERIFY_TARGET=chrome/common:common NINJA_JOBS=6 ./scripts/ci_verify_chromium.sh
