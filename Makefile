.PHONY: test test-ubuntu evidence-ubuntu dry-run

test:
	./tests/run.sh

test-ubuntu:
	./tests/run-ubuntu-integration.sh

evidence-ubuntu:
	COLLECT_EVIDENCE=1 ./tests/run-ubuntu-integration.sh

dry-run:
	./bin/setup-system.sh --reset-firewall --start-app
