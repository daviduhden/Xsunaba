# Variables
PREFIX ?= /usr/local
PROG = Xsunaba
SECTION = 1
BIN = bin
MAN = man
BINDIR = ${PREFIX}/${BIN}
MANDIR = ${PREFIX}/${MAN}/man${SECTION}
XSUNABA_USER ?= xsunaba
DOAS_LINE = "permit nopass ${USER} as ${XSUNABA_USER}"

# Default target
.PHONY: all
all: install

# Build target
.PHONY: build
build:
	@echo "Nothing to be built."

# Install target
.PHONY: install
install: ${BIN}/${PROG} ${MAN}/${PROG}.${SECTION} install-user install-doas
	mkdir -p ${BINDIR}
	install -m755 ${BIN}/${PROG} ${BINDIR}
	mkdir -p ${MANDIR}
	install -m444 ${MAN}/${PROG}.${SECTION} ${MANDIR}

# Install user target
.PHONY: install-user
install-user:
	id ${XSUNABA_USER} || useradd -m ${XSUNABA_USER}

# Install doas configuration target
.PHONY: install-doas
install-doas:
	! test -f /etc/doas.conf \
		&& touch /etc/doas.conf \
		&& chown root:wheel /etc/doas.conf \
		&& chmod 600 /etc.doas.conf
	grep -q "${DOAS_LINE}" /etc/doas.conf \
		|| echo "${DOAS_LINE}" >> /etc/doas.conf

# Install sndio cookie target
.PHONY: install-sndio-cookie
install-sndio-cookie:
	@echo "Copying sndio cookie from '${USER}' to '${XSUNABA_USER}'..."
	mkdir -p ~${XSUNABA_USER}/.sndio
	cp ~${USER}/.sndio/cookie ~${XSUNABA_USER}/.sndio/
	chown ${XSUNABA_USER}:${XSUNABA_USER} ~${XSUNABA_USER}/.sndio/cookie
	chmod 600 ~${XSUNABA_USER}/.sndio/cookie

# Uninstall target
.PHONY: uninstall
uninstall: uninstall-doas uninstall-user
	rm ${BINDIR}/${PROG}
	rm ${MANDIR}/${PROG}.${SECTION}

# Uninstall user target
.PHONY: uninstall-user
uninstall-user:
	rmuser ${XSUNABA_USER}

# Uninstall doas configuration target
.PHONY: uninstall-doas
uninstall-doas:
	test -f /etc/doas.conf \
		&& grep -p "${DOAS_LINE}" /etc/doas.conf \
		&& sed -i "s/${DOAS_LINE}//g" /etc/doas.conf

# Uninstall sndio cookie target
.PHONY: uninstall-sndio-cookie
uninstall-sndio-cookie:
	rm ~${XSUNABA_USER}/.sndio/cookie

# Help target
.PHONY: help
help:
	@echo "Makefile targets:"
	@echo "  all                  - Default target, installs the script and man page"
	@echo "  build                - Build target, does nothing"
	@echo "  install              - Installs the script and man page"
	@echo "  install-user         - Ensures the xsunaba user exists"
	@echo "  install-doas         - Configures doas for passwordless access"
	@echo "  install-sndio-cookie - Copies sndio cookie to xsunaba user"
	@echo "  uninstall            - Uninstalls the script and man page"
	@echo "  uninstall-user       - Removes the xsunaba user"
	@echo "  uninstall-doas       - Removes doas configuration"
	@echo "  uninstall-sndio-cookie - Removes sndio cookie from xsunaba user"
	@echo "  help                 - Displays this help message"
