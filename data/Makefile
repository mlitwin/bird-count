all: checklist

.PHONY: create
create:
	node ebird.js

.PHONY: checklist
checklist: create
	cp taxonomy.json ../src/data/
	cp checklist.json ../src/data/
