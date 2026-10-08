# See the LICENSE file at the top of the project tree for copyright
# and license details.

# Variables
PREFIX ?= /usr/local
PROG = Xsunaba
PROG_SRC = ${PROG}.pl
HELPER = xsunaba-helper
SECTION = 1
BIN = bin
LIBEXEC = libexec
MAN = man
BINDIR = ${PREFIX}/${BIN}
LIBEXECDIR = ${PREFIX}/${LIBEXEC}
MANDIR = ${PREFIX}/${MAN}/man${SECTION}
PROG_PATH = ${BIN}/${PROG_SRC}
HELPER_PATH = ${LIBEXEC}/${HELPER}
MAN_PATH = ${MAN}/${PROG}.${SECTION}
INFO = ==>

# Dedicated accounts. The Xephyr account owns the nested X server;
# the application account is a member of the shared group, which is
# the socket group. The invoking (login) user must not be a member.
XEPHYR_USER = _xsunaba_xephyr
APP_USER = _xsunaba_app
APP_GROUP = _xsunaba
APP_HOME = /home/${APP_USER}
APP_SHELL = /bin/ksh

.PHONY: all
all: install

.PHONY: build
build:
	@echo "${INFO} Nothing to build"

.PHONY: install
install: ${PROG_PATH} ${HELPER_PATH} ${MAN_PATH}
	@echo "${INFO} Installing ${PROG} -> ${BINDIR}/${PROG}" && \
		mkdir -p ${BINDIR} && \
		install -o root -g wheel -m755 ${PROG_PATH} ${BINDIR}/${PROG}
	@echo "${INFO} Installing helper -> ${LIBEXECDIR}/${HELPER}" && \
		mkdir -p ${LIBEXECDIR} && \
		install -o root -g wheel -m755 ${HELPER_PATH} \
		${LIBEXECDIR}/${HELPER}
	@echo "${INFO} Installing man page -> ${MANDIR}/${PROG}.${SECTION}" && \
		mkdir -p ${MANDIR} && \
		install -o root -g wheel -m444 ${MAN_PATH} ${MANDIR}
	@echo "${INFO} Install complete"
	@echo "${INFO} Next: 'doas make install-users' and review"
	@echo "${INFO} the doas rule printed by 'make show-doas-rule'"

# Create the dedicated accounts. Idempotent. Runs as root.
.PHONY: install-users
install-users:
	@grep -qs "^${APP_GROUP}:" /etc/group || \
		groupadd ${APP_GROUP}
	@id ${APP_USER} >/dev/null 2>&1 || \
		useradd -c 'Xsunaba sandbox application' \
		-d ${APP_HOME} -g ${APP_GROUP} -m \
		-s ${APP_SHELL} ${APP_USER}
	@id ${XEPHYR_USER} >/dev/null 2>&1 || \
		useradd -c 'Xsunaba Xephyr server' \
		-d /nonexistent -g =uid \
		-s /sbin/nologin ${XEPHYR_USER}
	@echo "${INFO} Accounts ${APP_USER}, ${XEPHYR_USER} and group"
	@echo "${INFO} ${APP_GROUP} are ready (home: ${APP_HOME})"

# Print the narrowest doas rule. Review and append to /etc/doas.conf
# manually; Xsunaba never edits /etc/doas.conf itself.
.PHONY: show-doas-rule
show-doas-rule:
	@printf '%s\n' "# Xsunaba: launch sandbox sessions through the root helper." \
	  "# doas inherits only DISPLAY and TERM by default; setenv keeps" \
	  "# the locale/timezone variables the helper forwards to the app." \
	  "permit nopass setenv { TZ LANG LC_ALL LC_CTYPE LC_MESSAGES } \\" \
	  "        USER as root cmd ${LIBEXECDIR}/${HELPER} \\" \
	  "        args --parent-display" \
	  "# Replace USER with your login name, or :wheel with a group."

.PHONY: uninstall
uninstall:
	@echo "${INFO} Removing ${BINDIR}/${PROG}"
	rm -f ${BINDIR}/${PROG}
	@echo "${INFO} Removing helper ${LIBEXECDIR}/${HELPER}"
	rm -f ${LIBEXECDIR}/${HELPER}
	@echo "${INFO} Removing man page ${MANDIR}/${PROG}.${SECTION}"
	rm -f ${MANDIR}/${PROG}.${SECTION}
	@echo "${INFO} Uninstall complete (accounts not removed)"

.PHONY: test
test:
	prove -I t/lib -v t/

# Build the optional X11 popup/pointer-grab regression tool used to
# validate input handling inside the nested server. Detection happens
# in the recipe with portable shell so this works with both GNU make
# and OpenBSD make: use pkg-config when present, otherwise the base
# X11 paths (OpenBSD has no pkg-config, but ships X11 in /usr/X11R6).
.PHONY: tools
tools: tools/popup-grab-test

tools/popup-grab-test: tools/popup-grab-test.c
	@if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists x11; \
	then \
		cc -Wall -Wextra -Wpedantic -Wshadow -Wconversion -O2 \
			$$(pkg-config --cflags x11) tools/popup-grab-test.c \
			-o $@ $$(pkg-config --libs x11); \
	else \
		cc -Wall -Wextra -Wpedantic -Wshadow -Wconversion -O2 \
			-I/usr/X11R6/include tools/popup-grab-test.c \
			-o $@ -L/usr/X11R6/lib -lX11; \
	fi

.PHONY: help
help:
	@printf '%s\n' '' 'Makefile targets:' \
	  '  all            - Default target, installs the script, helper and man page' \
	  '  build          - Build target, does nothing (pure Perl)' \
	  '  install        - Installs the script, helper and man page' \
	  '  install-users  - Creates the dedicated sandbox accounts (as root)' \
	  '  show-doas-rule - Prints the doas.conf rule to review and install' \
	  '  uninstall      - Removes the script, helper and man page' \
	  '  test           - Runs the regression tests' \
	  '  tools          - Builds the popup-grab input regression tool' \
	  '  clean          - Removes artifacts' \
	  '  help           - Displays this help message' ''

.PHONY: clean
clean:
	rm -f tools/popup-grab-test tools/popup-grab-test.log
	@echo "${INFO} Clean complete"
