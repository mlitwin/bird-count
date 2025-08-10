all: checklist

.PHONY: create
create:
	node ebird.js
	node validate

.PHONY: checklist
checklist: create
	cp taxonomy.json ../frontend/src/data
	cp checklist-US-CA-041.json ../frontend/src/data/checklist.json
