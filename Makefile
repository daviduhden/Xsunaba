# See the LICENSE file at the top of the project tree for copyright
# and license details.

# Variables
PREFIX ?= /usr/local
PROG = Xsunaba
PROG_SRC = ${PROG}.pl
PROG_PATH = ${.PARSEDIR}/${BIN}/${PROG_SRC}
SECTION = 1
BIN = bin
MAN = man
BINDIR = ${PREFIX}/${BIN}
MANDIR = ${PREFIX}/${MAN}/man${SECTION}
MAN_PATH = ${.PARSEDIR}/${MAN}/${PROG}.${SECTION}
INFO = ==>

.PHONY: all
all: install

.PHONY: build
build:
	@echo "${INFO} Nothing to build"

.PHONY: install
install: ${PROG_PATH} ${MAN_PATH}
	@echo "${INFO} Installing ${PROG} -> ${BINDIR}/${PROG}" && \
		mkdir -p ${BINDIR} && install -m755 ${PROG_PATH} ${BINDIR}/${PROG}
	@echo "${INFO} Installing man page -> ${MANDIR}/${PROG}.${SECTION}" && \
		mkdir -p ${MANDIR} && install -m444 ${MAN_PATH} ${MANDIR}
	@echo "${INFO} Install complete"

.PHONY: uninstall
uninstall:
	@echo "${INFO} Removing ${BINDIR}/${PROG}"
	rm ${BINDIR}/${PROG}
	@echo "${INFO} Removing man page ${MANDIR}/${PROG}.${SECTION}"
	rm ${MANDIR}/${PROG}.${SECTION}
	@echo "${INFO} Uninstall complete"

.PHONY: help
help:
	@printf "\nMakefile targets:\n\
	  all       - Default target, installs the script and man page\n\
	  build     - Build target, does nothing (pure Perl)\n\
	  install   - Installs the script and man page\n\
	  uninstall - Removes the script and man page\n\
	  clean     - Removes artifacts (none)\n\
	  test      - Placeholder for tests\n\
	  help      - Displays this help message\n\n"

.PHONY: clean
clean:
	@echo "${INFO} Nothing to clean"

.PHONY: test
test:
	@echo "${INFO} No automated tests defined"
