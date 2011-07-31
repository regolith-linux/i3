TOPDIR=$(shell pwd)

include $(TOPDIR)/common.mk

# Depend on the object files of all source-files in src/*.c and on all header files
AUTOGENERATED:=src/cfgparse.tab.c src/cfgparse.yy.c src/cmdparse.tab.c src/cmdparse.yy.c
FILES:=$(filter-out $(AUTOGENERATED),$(wildcard src/*.c))
FILES:=$(FILES:.c=.o)
HEADERS:=$(filter-out include/loglevels.h,$(wildcard include/*.h))

# Recursively generate loglevels.h by explicitly calling make
# We need this step because we need to ensure that loglevels.h will be
# updated if necessary, but we also want to save rebuilds of the object
# files, so we cannot let the object files depend on loglevels.h.
ifeq ($(MAKECMDGOALS),loglevels.h)
#UNUSED:=$(warning Generating loglevels.h)
else
UNUSED:=$(shell $(MAKE) loglevels.h)
endif

SUBDIRS=i3-msg i3-input i3-nagbar i3-config-wizard

# Depend on the specific file (.c for each .o) and on all headers
src/%.o: src/%.c ${HEADERS}
	echo "CC $<"
	$(CC) $(CPPFLAGS) $(CFLAGS) -DLOGLEVEL="((uint64_t)1 << $(shell awk '/$(shell basename $< .c)/ { print NR; exit 0; }' loglevels.tmp))" -c -o $@ $<

all: i3 subdirs

i3: src/cfgparse.y.o src/cfgparse.yy.o src/cmdparse.y.o src/cmdparse.yy.o ${FILES}
	echo "LINK i3"
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

subdirs:
	for dir in $(SUBDIRS); do \
		echo ""; \
		echo "MAKE $$dir"; \
		$(MAKE) -C $$dir; \
	done

loglevels.h:
	echo "LOGLEVELS"
	for file in $$(ls src/*.c src/*.y src/*.l | grep -v 'cfgparse.\(tab\|yy\).c'); \
	do \
		echo $$(basename $$file .c); \
	done > loglevels.tmp
	(echo "char *loglevels[] = {"; for file in $$(cat loglevels.tmp); \
	do \
		echo "\"$$file\", "; \
	done; \
	echo "};") > include/loglevels.h;

src/cfgparse.yy.o: src/cfgparse.l src/cfgparse.y.o ${HEADERS}
	echo "LEX $<"
	flex -i -o$(@:.o=.c) $<
	$(CC) $(CPPFLAGS) $(CFLAGS) -DLOGLEVEL="(1 << $(shell awk '/cfgparse.l/ { print NR }' loglevels.tmp))" -c -o $@ $(@:.o=.c)

src/cmdparse.yy.o: src/cmdparse.l src/cmdparse.y.o ${HEADERS}
	echo "LEX $<"
	flex -Pcmdyy -i -o$(@:.o=.c) $<
	$(CC) $(CPPFLAGS) $(CFLAGS) -DLOGLEVEL="(1 << $(shell awk '/cmdparse.l/ { print NR }' loglevels.tmp))" -c -o $@ $(@:.o=.c)


src/cfgparse.y.o: src/cfgparse.y ${HEADERS}
	echo "YACC $<"
	bison --debug --verbose -b $(basename $< .y) -d $<
	$(CC) $(CPPFLAGS) $(CFLAGS) -DLOGLEVEL="(1 << $(shell awk '/cfgparse.y/ { print NR }' loglevels.tmp))" -c -o $@ $(<:.y=.tab.c)

src/cmdparse.y.o: src/cmdparse.y ${HEADERS}
	echo "YACC $<"
	bison -p cmdyy --debug --verbose -b $(basename $< .y) -d $<
	$(CC) $(CPPFLAGS) $(CFLAGS) -DLOGLEVEL="(1 << $(shell awk '/cmdparse.y/ { print NR }' loglevels.tmp))" -c -o $@ $(<:.y=.tab.c)


install: all
	echo "INSTALL"
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/bin
	$(INSTALL) -d -m 0755 $(DESTDIR)$(SYSCONFDIR)/i3
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/include/i3
	$(INSTALL) -d -m 0755 $(DESTDIR)$(PREFIX)/share/xsessions
	$(INSTALL) -m 0755 i3 $(DESTDIR)$(PREFIX)/bin/
	$(INSTALL) -m 0755 i3-migrate-config-to-v4.pl $(DESTDIR)$(PREFIX)/bin/
	test -e $(DESTDIR)$(SYSCONFDIR)/i3/config || $(INSTALL) -m 0644 i3.config $(DESTDIR)$(SYSCONFDIR)/i3/config
	test -e $(DESTDIR)$(SYSCONFDIR)/i3/config.keycodes || $(INSTALL) -m 0644 i3.config.keycodes $(DESTDIR)$(SYSCONFDIR)/i3/config.keycodes
	$(INSTALL) -m 0644 i3.welcome $(DESTDIR)$(SYSCONFDIR)/i3/welcome
	$(INSTALL) -m 0644 i3.desktop $(DESTDIR)$(PREFIX)/share/xsessions/
	$(INSTALL) -m 0644 include/i3/ipc.h $(DESTDIR)$(PREFIX)/include/i3/
	for dir in $(SUBDIRS); do \
		$(MAKE) -C $$dir install; \
	done

dist: distclean
	[ ! -d i3-${VERSION} ] || rm -rf i3-${VERSION}
	[ ! -e i3-${VERSION}.tar.bz2 ] || rm i3-${VERSION}.tar.bz2
	mkdir i3-${VERSION}
	cp i3-migrate-config-to-v4.pl i3.config.keycodes DEPENDS GOALS LICENSE PACKAGE-MAINTAINER TODO RELEASE-NOTES-${VERSION} i3.config i3.desktop i3.welcome pseudo-doc.doxygen i3-wsbar Makefile i3-${VERSION}
	cp -r src i3-msg i3-nagbar i3-config-wizard yajl-fallback include man i3-${VERSION}
	# Only copy toplevel documentation (important stuff)
	mkdir i3-${VERSION}/docs
	# Pre-generate documentation
	make -C docs
	# Cleanup τεχ output files
	find docs -regex ".*\.\(aux\|out\|log\|toc\|bm\|dvi\|log\)" -exec rm '{}' \;
	find docs -maxdepth 1 -type f ! \( -name "*.xcf" -or -name "*.svg" \) -exec cp '{}' i3-${VERSION}/docs \;
	# Only copy source code from i3-input
	mkdir i3-${VERSION}/i3-input
	find i3-input -maxdepth 1 -type f \( -name "*.c" -or -name "*.h" -or -name "Makefile" \) -exec cp '{}' i3-${VERSION}/i3-input \;
	sed -e 's/^GIT_VERSION:=\(.*\)/GIT_VERSION:=$(shell echo '${GIT_VERSION}' | sed 's/\\/\\\\/g')/g;s/^VERSION:=\(.*\)/VERSION:=${VERSION}/g' common.mk > i3-${VERSION}/common.mk
	# Pre-generate a manpage to allow distributors to skip this step and save some dependencies
	$(MAKE) -C man
	cp man/*.1 i3-${VERSION}/man/
	tar cfj i3-${VERSION}.tar.bz2 i3-${VERSION}
	rm -rf i3-${VERSION}

clean:
	rm -f src/*.o src/*.gcno src/cfgparse.tab.{c,h} src/cfgparse.yy.c src/cfgparse.{output,dot} src/cmdparse.tab.{c,h} src/cmdparse.yy.c src/cmdparse.{output,dot} loglevels.tmp include/loglevels.h
	(which lcov >/dev/null && lcov -d . --zerocounters) || true
	$(MAKE) -C docs clean
	$(MAKE) -C man clean
	for dir in $(SUBDIRS); do \
		echo ""; \
		echo "CLEAN $$dir"; \
		$(MAKE) TOPDIR=$(TOPDIR) -C $$dir distclean; \
	done

distclean: clean
	rm -f i3
	for dir in $(SUBDIRS); do \
		echo ""; \
		echo "DISTCLEAN $$dir"; \
		$(MAKE) TOPDIR=$(TOPDIR) -C $$dir distclean; \
	done

coverage:
	rm -f /tmp/i3-coverage.info
	rm -rf /tmp/i3-coverage
	lcov -d . -b . --capture -o /tmp/i3-coverage.info
	genhtml -o /tmp/i3-coverage/ /tmp/i3-coverage.info
