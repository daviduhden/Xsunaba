install: bin/Xsunaba man/Xsunaba.1
	mkdir -p /usr/local/bin
	install -m755 bin/Xsunaba /usr/local/bin
	mkdir -p /usr/local/man/man1
	install -m444 man/Xsunaba.1 /usr/local/man/man1
	# Ensure the xsunaba user exists
	id xsunaba || useradd -m xsunaba
	# Add doas configuration for passwordless access (uncomment if needed)
	#grep -q "permit nopass ${USER} as xsunaba" /etc/doas.conf || echo "permit nopass ${USER} as xsunaba" >> /etc/doas.conf
