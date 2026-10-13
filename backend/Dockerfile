FROM debian:bookworm-slim

# Install Perl 5, DBI, DBD::mysql, and server essentials
RUN apt-get update && apt-get install -y --no-install-recommends \
    perl \
    libdbi-perl \
    libdbd-mysql-perl \
    libjson-pp-perl \
    libdigest-sha-perl \
    libmime-base64-perl \
    uwsgi \
    uwsgi-plugin-psgi \
    default-mysql-client \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy backend files
COPY . /app

EXPOSE 5000

CMD ["uwsgi", "--http-socket", "0.0.0.0:5000", "--plugin", "psgi", "--psgi", "web.pl", "--chdir", "/app", "--master", "--workers", "4", "--enable-threads", "--die-on-term"]

