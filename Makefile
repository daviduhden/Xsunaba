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
XSUNABA_USER ?= xsunaba
DOAS_LINE = permit nopass ${USER} as ${XSUNABA_USER}
INFO = ==>

# Default target
.PHONY: all
all: install

# Build target
.PHONY: build
build:
	@echo "${INFO} Nothing to build"

# Install target
.PHONY: install
install: ${PROG_PATH} ${MAN_PATH} install-user install-doas
	@echo "${INFO} Installing ${PROG} -> ${BINDIR}/${PROG}" && \
		mkdir -p ${BINDIR} && install -m755 ${PROG_PATH} ${BINDIR}/${PROG}
	@echo "${INFO} Installing man page -> ${MANDIR}/${PROG}.${SECTION}" && \
		mkdir -p ${MANDIR} && install -m444 ${MAN_PATH} ${MANDIR}
	@echo "${INFO} Install complete"

# Install user target
.PHONY: install-user
install-user:
	@echo "${INFO} Checking if the user ${XSUNABA_USER} exists"
	id ${XSUNABA_USER} || useradd -m ${XSUNABA_USER}

# Install doas configuration target
.PHONY: install-doas
install-doas:
	@echo "${INFO} Configuring doas for passwordless access"
	(test -f /etc/doas.conf || touch /etc/doas.conf) && chown root:wheel /etc/doas.conf && chmod 600 /etc/doas.conf
	grep -q "${DOAS_LINE}" /etc/doas.conf || echo "${DOAS_LINE}" >> /etc/doas.conf

# Install sndio cookie target
.PHONY: install-sndio-cookie
install-sndio-cookie:
	@echo "${INFO} Copying sndio cookie from '${USER}' to '${XSUNABA_USER}'"
	mkdir -p ~${XSUNABA_USER}/.sndio
	install -o ${XSUNABA_USER} -g ${XSUNABA_USER} -m 600 ~${USER}/.sndio/cookie ~${XSUNABA_USER}/.sndio/

# Uninstall target
.PHONY: uninstall
uninstall: uninstall-doas uninstall-user
	@echo "${INFO} Removing ${BINDIR}/${PROG}"
	rm ${BINDIR}/${PROG}
	@echo "${INFO} Removing man page ${MANDIR}/${PROG}.${SECTION}"
	rm ${MANDIR}/${PROG}.${SECTION}
	@echo "${INFO} Uninstall complete"

# Uninstall user target
.PHONY: uninstall-user
uninstall-user:
	@echo "${INFO} Removing the user ${XSUNABA_USER}"
	rmuser ${XSUNABA_USER}

# Uninstall doas configuration target
.PHONY: uninstall-doas
uninstall-doas:
	@echo "${INFO} Removing doas configuration"
	test -f /etc/doas.conf \
		&& grep -p "${DOAS_LINE}" /etc/doas.conf \
		&& sed -i "s/${DOAS_LINE}//g" /etc/doas.conf

# Uninstall sndio cookie target
.PHONY: uninstall-sndio-cookie
uninstall-sndio-cookie:
	@echo "${INFO} Removing sndio cookie from ${XSUNABA_USER}"
	rm ~${XSUNABA_USER}/.sndio/cookie

# Help target
.PHONY: help
help:
	@printf "Makefile targets:\n  all                  - Default target, installs the script and man page\n  build                - Build target, does nothing\n  install              - Installs the script and man page\n  install-user         - Ensures the xsunaba user exists\n  install-doas         - Configures doas for passwordless access\n  install-sndio-cookie - Copies sndio cookie to xsunaba user\n  uninstall            - Uninstalls the script and man page\n  uninstall-user       - Removes the xsunaba user\n  uninstall-doas       - Removes doas configuration\n  uninstall-sndio-cookie - Removes sndio cookie from xsunaba user\n  clean                - Removes build artifacts\n  test                 - Placeholder for tests\n  help                 - Displays this help message\n"

.PHONY: clean
clean:
	@echo "${INFO} Nothing to clean"

.PHONY: test
test:
	@echo "${INFO} No automated tests defined"