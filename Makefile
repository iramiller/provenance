#!/usr/bin/make -f
export GO111MODULE=on

PACKAGES               := $(shell go list ./... 2>/dev/null || true)
PACKAGES_NOSIMULATION  := $(filter-out %/simulation%,$(PACKAGES))
PACKAGES_SIMULATION    := $(filter     %/simulation%,$(PACKAGES))

LEVELDB_PATH := $(shell brew --prefix leveldb 2>/dev/null || echo "$(HOME)/Cellar/leveldb/1.22/include")
CGO_CFLAGS := -I$(LEVELDB_PATH)/include
CGO_LDFLAGS := -L$(LEVELDB_PATH)/lib

BINDIR ?= $(GOPATH)/bin
BUILDDIR ?= $(CURDIR)/build

LEDGER_ENABLED ?= true
WITH_CLEVELDB ?= yes

VERSION := $(shell ( git describe --tags 2>/dev/null || echo "v0.0.0" ) | sed 's/^v//')
COMMIT := $(shell git log -1 --format='%H')

GO := go

# The below include contains the tools target.
include contrib/devtools/Makefile


##############################
# Build Flags/Tags
##############################
build_tags = netgo
ifeq ($(WITH_CLEVELDB),yes)
  build_tags += gcc
  build_tags += cleveldb
endif

ifeq ($(LEDGER_ENABLED),true)
  ifeq ($(OS),Windows_NT)
    GCCEXE = $(shell where gcc.exe 2> NUL)
    ifeq ($(GCCEXE),)
      $(error gcc.exe not installed for ledger support, please install or set LEDGER_ENABLED=false)
    else
      build_tags += ledger
    endif
  else
    UNAME_S = $(shell uname -s)
    ifeq ($(UNAME_S),OpenBSD)
      $(warning OpenBSD detected, disabling ledger support (https://github.com/cosmos/cosmos-sdk/issues/1988))
    else
      GCC = $(shell command -v gcc 2> /dev/null)
      ifeq ($(GCC),)
        $(error gcc not installed for ledger support, please install or set LEDGER_ENABLED=false)
      else
        build_tags += ledger
      endif
    endif
  endif
endif

build_tags += $(BUILD_TAGS)
build_tags := $(strip $(build_tags))
whitespace :=
whitespace += $(whitespace)
comma := ,
build_tags_comma_sep := $(subst $(whitespace),$(comma),$(build_tags))

ldflags = -w -s \
	-X github.com/cosmos/cosmos-sdk/version.Name=Provenance \
	-X github.com/cosmos/cosmos-sdk/version.AppName=provenanced \
	-X github.com/cosmos/cosmos-sdk/version.Version=$(VERSION) \
	-X github.com/cosmos/cosmos-sdk/version.Commit=$(COMMIT) \
	-X "github.com/cosmos/cosmos-sdk/version.BuildTags=$(build_tags_comma_sep)"

ifeq ($(WITH_CLEVELDB),yes)
	ldflags += -X github.com/cosmos/cosmos-sdk/types.DBBackend=cleveldb
endif
ldflags += $(LDFLAGS)
ldflags := $(strip $(ldflags))
BUILD_FLAGS := -tags "$(build_tags)" -ldflags '$(ldflags)' -trimpath

all: build format lint test

.PHONY: all


##############################
# Build
##############################

# Install puts the binaries in the local environment path.
install: go.sum
	CGO_LDFLAGS=$(CGO_LDFLAGS) CGO_CFLAGS=$(CGO_CFLAGS) $(GO) install -mod=readonly $(BUILD_FLAGS) ./cmd/provenanced

build: go.sum
	mkdir -p $(BUILDDIR)
	CGO_LDFLAGS=$(CGO_LDFLAGS) CGO_CFLAGS=$(CGO_CFLAGS) $(GO) build -mod=readonly $(BUILD_FLAGS) -o $(BUILDDIR)/ ./cmd/provenanced

build-linux: go.sum
	LEDGER_ENABLED=false GOOS=linux GOARCH=amd64 $(MAKE) build

# Run an instance of the daemon against a local config (create the config if it does not exit.)
run-config:
	@if [ ! -d "$(BUILDDIR)/run/provenanced/config" ]; then \
		$(BUILDDIR)/provenanced -t --home $(BUILDDIR)/run/provenanced init --chain-id=testing testing ; \
		$(BUILDDIR)/provenanced -t --home $(BUILDDIR)/run/provenanced keys add validator --keyring-backend test ; \
		$(BUILDDIR)/provenanced -t --home $(BUILDDIR)/run/provenanced add-genesis-root-name validator pio --keyring-backend test ; \
		$(BUILDDIR)/provenanced -t --home $(BUILDDIR)/run/provenanced add-genesis-root-name validator pb --restrict=false --keyring-backend test ; \
		$(BUILDDIR)/provenanced -t --home $(BUILDDIR)/run/provenanced add-genesis-root-name validator io --restrict --keyring-backend test ; \
		$(BUILDDIR)/provenanced -t --home $(BUILDDIR)/run/provenanced add-genesis-root-name validator provenance --keyring-backend test ; \
		$(BUILDDIR)/provenanced -t --home $(BUILDDIR)/run/provenanced add-genesis-account validator 100000000000000000000nhash --keyring-backend test ; \
		$(BUILDDIR)/provenanced -t --home $(BUILDDIR)/run/provenanced gentx validator 1000000000000000nhash --keyring-backend test --chain-id=testing; \
		$(BUILDDIR)/provenanced -t --home $(BUILDDIR)/run/provenanced collect-gentxs; \
	fi ;

run: check-built run-config;
	$(BUILDDIR)/provenanced -t --home $(BUILDDIR)/run/provenanced start

.PHONY: install build build-linux run



##############################
# Tools / Dependencies
##############################

go-mod-cache: go.sum
	@echo "--> Download go modules to local cache"
	@go mod download
.PHONY: go-mod-cache

go.sum: go.mod
	@echo "--> Ensure dependencies have not been modified"
	@go mod verify
	@go mod tidy

# look into .golangci.yml for enabling / disabling linters
lint:
	$(BINDIR)/golangci-lint run
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "*.pb.go" | xargs gofmt -d -s
	$(GO) mod verify

clean:
	rm -rf $(BUILDDIR)/*

format:
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "*.pb.go" | xargs gofmt -w -s
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "*.pb.go" | xargs misspell -w
	find . -name '*.go' -type f -not -path "./vendor*" -not -path "*.git*" -not -path "*.pb.go" | xargs goimports -w -local github.com/provenance-io/provenance

check-built:
	@if [ ! -f "$(BUILDDIR)/provenanced" ]; then \
		echo "\n fatal: Nothing to run.  Try 'make build' first.\n" ; \
		exit 1; \
	fi

statik:
	$(GO) get -u github.com/rakyll/statik
	$(GO) generate ./api/...

.PHONY: go-mod-cache go.sum lint clean format check-built statik


##############################
### Test
##############################

include sims.mk

test: test-unit
test-all: test-unit test-race test-cover

test-unit:
	@VERSION=$(VERSION) go test -mod=readonly  -tags='ledger test_ledger_mock' $(PACKAGES_NOSIMULATION)

test-race:
	@VERSION=$(VERSION) go test -mod=readonly -race  -tags='ledger test_ledger_mock' $(PACKAGES_NOSIMULATION)

test-cover:
	@go test -mod=readonly -timeout 30m -race -coverprofile=coverage.txt -covermode=atomic -tags='ledger test_ledger_mock' ./...

test-build: build
	@go test -mod=readonly -p 4 `go list ./cli_test/...` -tags=cli_test -v

benchmark:
	@go test -mod=readonly -bench=. ./...

.PHONY: test test-all test-unit test-race test-cover test-build benchmark


##############################
# Proto -> golang compilation
##############################
proto-all: proto-tools proto-gen proto-lint proto-check-breaking proto-swagger-gen proto-format protoc-gen-gocosmos protoc-gen-grpc-gateway

proto-gen:
	@./scripts/protocgen.sh

proto-format:
	find ./ -not -path "*/third_party/*" -name *.proto -exec clang-format -i {} \;

# This generates the SDK's custom wrapper for google.protobuf.Any. It should only be run manually when needed
proto-gen-any:
	@./scripts/protocgen-any.sh

proto-swagger-gen:
	@./scripts/protoc-swagger-gen.sh

proto-lint:
	@buf check lint --error-format=json

proto-check-breaking:
	@buf check breaking --against-input '.git#branch=main'

proto-lint-docker:
	@$(DOCKER_BUF) check lint --error-format=json

proto-check-breaking-docker:
	@$(DOCKER_BUF) check breaking --against-input $(HTTPS_GIT)#branch=main

TM_URL           = https://raw.githubusercontent.com/tendermint/tendermint/v0.34.x/proto/tendermint
GOGO_PROTO_URL   = https://raw.githubusercontent.com/regen-network/protobuf/cosmos
COSMOS_PROTO_URL = https://raw.githubusercontent.com/regen-network/cosmos-proto/master
COSMOS_SDK_URL   = https://raw.githubusercontent.com/cosmos/cosmos-sdk/v0.40.x/proto/cosmos
CONFIO_URL       = https://raw.githubusercontent.com/confio/ics23/v0.6.3

TM_CRYPTO_TYPES     = third_party/proto/tendermint/crypto
TM_ABCI_TYPES       = third_party/proto/tendermint/abci
TM_TYPES            = third_party/proto/tendermint/types
TM_VERSION          = third_party/proto/tendermint/version
TM_LIBS             = third_party/proto/tendermint/libs/bits

GOGO_PROTO_TYPES     = third_party/proto/gogoproto
COSMOS_PROTO_TYPES   = third_party/proto/cosmos_proto
COSMOS_BASE_TYPES    = third_party/proto/cosmos/base
COSMOS_SIGNING_TYPES = third_party/proto/cosmos/tx/signing
COSMOS_CRYPTO_TYPES  = third_party/proto/cosmos/crypto
COSMOS_AUTH_TYPES    = third_party/proto/cosmos/auth
CONFIO_TYPES         = third_party/proto/confio

proto-update-deps:
	@mkdir -p $(GOGO_PROTO_TYPES)
	@curl -sSL $(GOGO_PROTO_URL)/gogoproto/gogo.proto > $(GOGO_PROTO_TYPES)/gogo.proto

	@mkdir -p $(COSMOS_PROTO_TYPES)
	@curl -sSL $(COSMOS_PROTO_URL)/cosmos.proto > $(COSMOS_PROTO_TYPES)/cosmos.proto

	@mkdir -p $(COSMOS_BASE_TYPES)/v1beta1
	@curl -sSL $(COSMOS_SDK_URL)/base/v1beta1/coin.proto > $(COSMOS_BASE_TYPES)/v1beta1/coin.proto

	@mkdir -p $(COSMOS_BASE_TYPES)/v1beta1
	@curl -sSL $(COSMOS_SDK_URL)/base/v1beta1/coin.proto > $(COSMOS_BASE_TYPES)/v1beta1/coin.proto

	@mkdir -p $(COSMOS_SIGNING_TYPES)/v1beta1
	@curl -sSL $(COSMOS_SDK_URL)/tx/signing/v1beta1/signing.proto > $(COSMOS_SIGNING_TYPES)/v1beta1/signing.proto

	@mkdir -p $(COSMOS_CRYPTO_TYPES)/secp256k1
	@curl -sSL $(COSMOS_SDK_URL)/crypto/secp256k1/keys.proto > $(COSMOS_CRYPTO_TYPES)/secp256k1/keys.proto

	@mkdir -p $(COSMOS_CRYPTO_TYPES)/multisig/v1beta1
	@curl -sSL $(COSMOS_SDK_URL)/crypto//multisig/v1beta1/multisig.proto > $(COSMOS_CRYPTO_TYPES)/multisig/v1beta1/multisig.proto

	@mkdir -p $(COSMOS_AUTH_TYPES)/v1beta1
	@curl -sSL $(COSMOS_SDK_URL)/auth/v1beta1/auth.proto > $(COSMOS_AUTH_TYPES)/v1beta1/auth.proto

	@mkdir -p $(TM_ABCI_TYPES)
	@curl -sSL $(TM_URL)/abci/types.proto > $(TM_ABCI_TYPES)/types.proto

	@mkdir -p $(TM_VERSION)
	@curl -sSL $(TM_URL)/version/types.proto > $(TM_VERSION)/types.proto

	@mkdir -p $(TM_TYPES)
	@curl -sSL $(TM_URL)/types/types.proto > $(TM_TYPES)/types.proto
	@curl -sSL $(TM_URL)/types/evidence.proto > $(TM_TYPES)/evidence.proto
	@curl -sSL $(TM_URL)/types/params.proto > $(TM_TYPES)/params.proto
	@curl -sSL $(TM_URL)/types/validator.proto > $(TM_TYPES)/validator.proto

	@mkdir -p $(TM_CRYPTO_TYPES)
	@curl -sSL $(TM_URL)/crypto/proof.proto > $(TM_CRYPTO_TYPES)/proof.proto
	@curl -sSL $(TM_URL)/crypto/keys.proto > $(TM_CRYPTO_TYPES)/keys.proto

	@mkdir -p $(TM_LIBS)
	@curl -sSL $(TM_URL)/libs/bits/types.proto > $(TM_LIBS)/types.proto

	@mkdir -p $(CONFIO_TYPES)
	@curl -sSL $(CONFIO_URL)/proofs.proto > $(CONFIO_TYPES)/proofs.proto.orig
## insert go, java package option into proofs.proto file
## Issue link: https://github.com/confio/ics23/issues/32 (instead of a simple sed we need 4 lines cause bsd sed -i is incompatible)
	@head -n3 $(CONFIO_TYPES)/proofs.proto.orig > $(CONFIO_TYPES)/proofs.proto
	@echo 'option go_package = "github.com/confio/ics23/go";' >> $(CONFIO_TYPES)/proofs.proto 
	@echo 'option java_package = "tech.confio.ics23";' >> $(CONFIO_TYPES)/proofs.proto
	@echo 'option java_multiple_files = true;' >> $(CONFIO_TYPES)/proofs.proto
	@tail -n+4 $(CONFIO_TYPES)/proofs.proto.orig >> $(CONFIO_TYPES)/proofs.proto 
	@rm $(CONFIO_TYPES)/proofs.proto.orig

.PHONY: proto-all proto-gen proto-format proto-gen-any proto-swagger-gen proto-lint proto-check-breaking 
.PHONY: proto-lint-docker proto-check-breaking-docker proto-update-deps


##############################
### Docs
##############################
update-swagger-docs: statik
	$(BINDIR)/statik -src=client/docs/swagger-ui -dest=client/docs -f -m
	@if [ -n "$(git status --porcelain)" ]; then \
        echo "Swagger docs are out of sync";\
        exit 1;\
    else \
    	echo "Swagger docs are in sync";\
    fi

.PHONY: update-swagger-docs