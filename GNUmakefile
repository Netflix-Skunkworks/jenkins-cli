SRC=bin/jenkins $(shell find lib -name \*.pm)

.PHONY: static
static: $(SRC)
	head -1 bin/jenkins > jenkins-static
	find lib -depth -name \*.pm | xargs cat | grep -v "^use WWW::Jenkins" >> jenkins-static
	echo "package main;" >> jenkins-static
	cat bin/jenkins | grep -v "^use WWW::Jenkins" >> jenkins-static
	chmod 755 ./jenkins-static