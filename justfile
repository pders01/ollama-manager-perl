# justfile for ollama-manager-perl

# Install Perl dependencies using cpanm
install:
    cpanm --notest --installdeps .

# Run Perl tests
# Use `just test` to run all tests
# Use `just test t/01-basic.t` to run a specific test
# Use `just test TESTARGS='-v t/01-basic.t'` for custom args
TESTARGS := "-lv t"
test:
    prove {{TESTARGS}}

# Build the Docker image
# Use `just docker-build` to build the image
# Use `just docker-build TAG=ollama-manager-perl-cli` to specify a tag
TAG := "ollama-manager-perl-cli"
docker-build:
    docker-buildx build -t {{TAG}} .

# Run the Docker container
# Use `just docker-run` to run the container
# Use `just docker-run TAG=ollama-manager-perl-cli` to specify a tag
# Use `just docker-run CMD='prove -lv t'` to override the command
CMD := "prove -lv t"
docker-run:
    docker run --rm -it {{TAG}} {{CMD}}
