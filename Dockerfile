# Use the official Perl image
FROM perl:latest

# Install system dependencies for building Perl modules and Ollama
RUN apt-get update && \
    apt-get install -y curl sudo git build-essential && \
    rm -rf /var/lib/apt/lists/*

# Set workdir
WORKDIR /usr/src/app

# Copy project files
COPY . .

# Set PERL5LIB so Perl can find local modules
ENV PERL5LIB=/usr/src/app/lib

# Install CPAN dependencies (add more as needed)
RUN cpanm --notest Test::More Test::Exception Time::HiRes && \
    cpanm --installdeps .

# Quick check for the user
RUN whoami

# Install Ollama using the library, if not already installed
RUN perl -MOllama::Manager -e 'Ollama::Manager->new->install unless Ollama::Manager->new->is_installed'

# Optionally, install Ollama here if possible (stubbed)
# RUN curl -fsSL https://ollama.com/download.sh | sh

# Default command: run all tests
CMD ["sh", "-c", "ollama --version && ollama serve & sleep 2 && bash"]