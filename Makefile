.PHONY: all clean regenerate-data

all:
	make -C boomerang
	make -C paper

clean:
	make -C boomerang clean
	make -C paper clean

regenerate-data:
	make -C boomerang generate-data
	cp -r boomerang/generated_data .
	python transform-data.py generated_data/bijective_data.csv generated_data/symmetric_data.csv
	cp -r generated-graphs paper
	make -C paper
