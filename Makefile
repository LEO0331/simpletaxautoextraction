.PHONY: e2e-web

e2e-web:
	flutter pub run patrol_cli:main test --target patrol_test/web_smoke_test.dart -d chrome
