.PHONY: help version release-patch release-minor release-major release push ship-patch ship-minor ship-major

help:
	@echo "VCamdroid release (run from repo root):"
	@echo "  make ship-patch|ship-minor|ship-major   bump version, commit, tag, push → GitHub Release CI"
	@echo "  make release-patch && make push         same, in two steps"
	@echo "  make version                            print VERSION"
	@echo "See docs/CI-AND-RELEASE.md for CI assumptions and troubleshooting."

version:
	@cat VERSION

release-patch:
	@$(MAKE) release BUMP=patch

release-minor:
	@$(MAKE) release BUMP=minor

release-major:
	@$(MAKE) release BUMP=major

ship-patch:
	@$(MAKE) release BUMP=patch && $(MAKE) push

ship-minor:
	@$(MAKE) release BUMP=minor && $(MAKE) push

ship-major:
	@$(MAKE) release BUMP=major && $(MAKE) push

release:
ifndef BUMP
	$(error Usage: make release-patch, make release-minor, or make release-major — or make ship-* to push immediately)
endif
	@echo ""
	@./scripts/bump-version.sh $(BUMP)
	@NEW_VERSION=$$(tr -d '[:space:]' < VERSION); \
	git add VERSION android/app/build.gradle.kts ios/VCamdroidiOS/Sources/VCamdroidiOS/Info.plist windows/vcpkg.json; \
	git commit -m "release: v$$NEW_VERSION"; \
	git tag "v$$NEW_VERSION"; \
	echo ""; \
	echo "Tagged v$$NEW_VERSION"; \
	echo ""; \
	echo "Run 'make push' to push and trigger the release build."; \
	echo "Or use 'make ship-$(BUMP)' next time to push in one step."

push:
	git push origin HEAD --tags
	@echo ""
	@echo "Pushed. GitHub Actions will now build and create the release."
