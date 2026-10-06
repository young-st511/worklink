.PHONY: probe clean build app test previews icon-previews

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

icon-previews:
	sh scripts/render-icon.sh

probe: .build/clipboard-cost

.build/clipboard-cost: experiments/clipboard-cost.swift
	mkdir -p .build
	xcrun swiftc -O $< -o $@

clean:
	rm -rf .build
