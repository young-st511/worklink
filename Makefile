.PHONY: probe clean build app test previews

build:
	mkdir -p .build
	go build -o .build/worklink ./cmd/worklink

app:
	sh scripts/build-app.sh

test:
	go test -race ./...
	go vet ./...

previews: app
	.build/Worklink.app/Contents/MacOS/Worklink --self-test
	.build/Worklink.app/Contents/MacOS/Worklink --render-previews .build/previews

probe: .build/clipboard-cost

.build/clipboard-cost: experiments/clipboard-cost.swift
	mkdir -p .build
	xcrun swiftc -O $< -o $@

clean:
	rm -rf .build
