DESTINATION ?= platform=iOS Simulator,name=iPhone 16,OS=latest
DESTINATIONS ?= -destination '$(DESTINATION)'
XCODEBUILD ?= xcodebuild

.PHONY: test test-many test-circle-ci publish-pod

test:
	$(XCODEBUILD) test -project Tests/WebViewJavascriptBridge.xcodeproj -scheme WebViewJavascriptBridge $(DESTINATIONS)

test-many test-circle-ci: test

publish-pod:
	# pod trunk register narcvs@gmail.com 'Marcus Westin' --description='MBA/MBP-xyz'
	# First, bump podspec version, then commit & create tag: `git tag -a "v5.X.Y" -m "Tag v5.X.Y" && git push --tags`
	pod trunk push --verbose WebViewJavascriptBridge.podspec
