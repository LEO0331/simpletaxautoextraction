.PHONY: e2e-web

e2e-web:
	flutter drive --driver=test_driver/release_browser_test.dart --target=integration_test/release_browser_test.dart -d web-server --browser-name=chrome --headless --web-port=7357
