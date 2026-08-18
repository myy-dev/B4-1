.PHONY: test test-ubuntu dry-run

test:
	./tests/run.sh

test-ubuntu:
	./tests/run-ubuntu-integration.sh

dry-run:
	./bin/setup-system.sh --reset-firewall --start-app
