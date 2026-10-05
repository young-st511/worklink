.PHONY: probe clean

probe: .build/clipboard-cost

.build/clipboard-cost: experiments/clipboard-cost.swift
	mkdir -p .build
	xcrun swiftc -O $< -o $@

clean:
	rm -rf .build
