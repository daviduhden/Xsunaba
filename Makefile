# Variables
BIN_DIR=/usr/local/bin
MAN_DIR=/usr/local/man/man1
XSUNABA_USER=xsunaba

# Default target
.PHONY: all
all: install

# Install target
.PHONY: install
install: bin/Xsunaba man/Xsunaba.1
	@echo "Creating $(BIN_DIR) directory..."
	mkdir -p $(BIN_DIR)
	@echo "Installing Xsunaba script to $(BIN_DIR)..."
	install -m755 bin/Xsunaba $(BIN_DIR)
	@echo "Creating $(MAN_DIR) directory..."
	mkdir -p $(MAN_DIR)
	@echo "Installing Xsunaba man page to $(MAN_DIR)..."
	install -m444 man/Xsunaba.1 $(MAN_DIR)
	@echo "Ensuring the $(XSUNABA_USER) user exists..."
	id $(XSUNABA_USER) || useradd -m $(XSUNABA_USER)
	@echo "Installation complete."
	# Add doas configuration for passwordless access (uncomment if needed)
	#grep -q "permit nopass ${USER} as $(XSUNABA_USER)" /etc/doas.conf || echo "permit nopass ${USER} as $(XSUNABA_USER)" >> /etc/doas.conf

# Uninstall target
.PHONY: uninstall
uninstall:
	@echo "Removing Xsunaba script from $(BIN_DIR)..."
	rm -f $(BIN_DIR)/Xsunaba
	@echo "Removing Xsunaba man page from $(MAN_DIR)..."
	rm -f $(MAN_DIR)/Xsunaba.1
	@echo "Uninstallation complete."

# Help target
.PHONY: help
help:
	@echo "Makefile targets:"
	@echo "  all        - Default target, installs the script and man page"
	@echo "  install    - Installs the script and man page"
	@echo "  uninstall  - Uninstalls the script and man page"
	@echo "  help       - Displays this help message"
