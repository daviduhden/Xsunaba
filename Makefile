install: bin/Xsunaba man/Xsunaba.1
	@echo "Creating /usr/local/bin directory..."
	mkdir -p /usr/local/bin
	@echo "Installing Xsunaba script to /usr/local/bin..."
	install -m755 bin/Xsunaba /usr/local/bin
	@echo "Creating /usr/local/man/man1 directory..."
	mkdir -p /usr/local/man/man1
	@echo "Installing Xsunaba man page to /usr/local/man/man1..."
	install -m444 man/Xsunaba.1 /usr/local/man/man1
	@echo "Ensuring the xsunaba user exists..."
	id xsunaba || useradd -m xsunaba
	@echo "Installation complete."
	# Add doas configuration for passwordless access (uncomment if needed)
	#grep -q "permit nopass ${USER} as xsunaba" /etc/doas.conf || echo "permit nopass ${USER} as xsunaba" >> /etc/doas.conf
