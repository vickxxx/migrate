SOURCE ?= file go-bindata github aws-s3 google-cloud-storage
DATABASE ?= postgres mysql redshift cassandra sqlite3 spanner cockroachdb clickhouse
VERSION ?= $(shell git describe --tags 2>/dev/null | cut -c 2-)
TEST_FLAGS ?=
REPO_OWNER ?= $(shell cd .. && basename "$$(pwd)")


build-cli: clean
	-mkdir ./cli/build
	cd ./cli && CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -a -o build/migrate.linux-amd64 -ldflags='-X main.Version=$(VERSION)' -tags '$(DATABASE) $(SOURCE)' .
	cd ./cli && CGO_ENABLED=1 GOOS=darwin GOARCH=amd64 go build -a -o build/migrate.darwin-amd64 -ldflags='-X main.Version=$(VERSION)' -tags '$(DATABASE) $(SOURCE)' .
	cd ./cli && CGO_ENABLED=1 GOOS=windows GOARCH=amd64 go build -a -o build/migrate.windows-amd64.exe -ldflags='-X main.Version=$(VERSION)' -tags '$(DATABASE) $(SOURCE)' .
	cd ./cli/build && find . -name 'migrate*' | xargs -I{} tar czf {}.tar.gz {}
	cd ./cli/build && shasum -a 256 * > sha256sum.txt
	cat ./cli/build/sha256sum.txt


clean:
	-rm -r ./cli/build


test-short:
	make test-with-flags --ignore-errors TEST_FLAGS='-short'


test:
	@-rm -r .coverage
	@mkdir .coverage
	make test-with-flags TEST_FLAGS='-v -race -covermode atomic -coverprofile .coverage/_$$(RAND).txt -bench=. -benchmem'
	@echo 'mode: atomic' > .coverage/combined.txt
	@cat .coverage/*.txt | grep -v 'mode: atomic' >> .coverage/combined.txt


test-with-flags:
	@echo SOURCE: $(SOURCE) 
	@echo DATABASE: $(DATABASE)

	@go test $(TEST_FLAGS) .
	@go test $(TEST_FLAGS) ./cli/...
	@go test $(TEST_FLAGS) ./testing/...

	@echo -n '$(SOURCE)' | tr -s ' ' '\n' | xargs -I{} go test $(TEST_FLAGS) ./source/{}
	@go test $(TEST_FLAGS) ./source/testing/...
	@go test $(TEST_FLAGS) ./source/stub/...

	@echo -n '$(DATABASE)' | tr -s ' ' '\n' | xargs -I{} go test $(TEST_FLAGS) ./database/{}
	@go test $(TEST_FLAGS) ./database/testing/...
	@go test $(TEST_FLAGS) ./database/stub/...


kill-orphaned-docker-containers:
	docker rm -f $(shell docker ps -aq --filter label=migrate_test)


html-coverage:
	go tool cover -html=.coverage/combined.txt


deps:
	-go get -v -u ./... 
	-go test -v -i ./...
	# TODO: why is this not being fetched with the command above?
	-go get -u github.com/fsouza/fake-gcs-server/fakestorage


list-external-deps:
	$(call external_deps,'.')
	$(call external_deps,'./cli/...')
	$(call external_deps,'./testing/...')

	$(foreach v, $(SOURCE), $(call external_deps,'./source/$(v)/...'))
	$(call external_deps,'./source/testing/...')
	$(call external_deps,'./source/stub/...')

	$(foreach v, $(DATABASE), $(call external_deps,'./database/$(v)/...'))
	$(call external_deps,'./database/testing/...')
	$(call external_deps,'./database/stub/...')


restore-import-paths:
	find . -name '*.go' -type f -execdir sed -i '' s%\"github.com/$(REPO_OWNER)/migrate%\"github.com/vickxxx/migrate%g '{}' \;


rewrite-import-paths:
	find . -name '*.go' -type f -execdir sed -i '' s%\"github.com/vickxxx/migrate%\"github.com/$(REPO_OWNER)/migrate%g '{}' \;


# example: fswatch -0 --exclude .godoc.pid --event Updated . | xargs -0 -n1 -I{} make docs
docs:
	-make kill-docs
	nohup godoc -play -http=127.0.0.1:6064 </dev/null >/dev/null 2>&1 & echo $$! > .godoc.pid
	cat .godoc.pid  


kill-docs:
	@cat .godoc.pid
	kill -9 $$(cat .godoc.pid)
	rm .godoc.pid


open-docs:
	open http://localhost:6064/pkg/github.com/$(REPO_OWNER)/migrate


# example: make release V=0.0.0
release:
	git tag v$(V)
	@read -p "Press enter to confirm and push to origin ..." && git push origin v$(V)


define external_deps
	@echo '-- $(1)';  go list -f '{{join .Deps "\n"}}' $(1) | grep -v github.com/$(REPO_OWNER)/migrate | xargs go list -f '{{if not .Standard}}{{.ImportPath}}{{end}}'

endef


.PHONY: build-cli clean test-short test test-with-flags deps html-coverage \
        restore-import-paths rewrite-import-paths list-external-deps release \
        docs kill-docs open-docs kill-orphaned-docker-containers

SHELL = /bin/bash
RAND = $(shell echo $$RANDOM)

