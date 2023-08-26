all: checklist

.PHONY: create
create:
	node ebird.js
	node validate

.PHONY: checklist
checklist: create
	cp taxonomy.json ../frontend/src/data
	cp checklist*.json ../frontend/src/data
