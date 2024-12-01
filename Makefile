CRI ?= podman

lint-check:
	tidyall --check --git --no-cache --no-cleanup --no-backups

lint-fix:
	tidyall --git --no-cache --no-cleanup --no-backups

critic:
	perlcritic *.pl

devel-server:
	perl devel_server.pl daemon

devel-rabbitmq:
	$(CRI) stop ratoh-rabbitmq || true
	$(CRI) rm -f ratoh-rabbitmq || true
	$(CRI) run -d --name ratoh-rabbitmq --rm -it -p 5672:5672 rabbitmq:3
