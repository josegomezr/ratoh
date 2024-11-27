lint-check:
	tidyall --check --git --no-cache --no-cleanup --no-backups

lint-fix:
	tidyall --git --no-cache --no-cleanup --no-backups

critic:
	perlcritic *.pl
