.PHONY: release-patch release-minor release-major release version

version:
	@cat VERSION

release-patch:
	@$(MAKE) release BUMP=patch

release-minor:
	@$(MAKE) release BUMP=minor

release-major:
	@$(MAKE) release BUMP=major

release:
ifndef BUMP
	$(error Usage: make release-patch, make release-minor, or make release-major)
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
	echo "Or 'git push origin main --tags' manually."

push:
	git push origin HEAD --tags
	@echo ""
	@echo "Pushed. GitHub Actions will now build and create the release."
