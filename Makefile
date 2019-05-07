.PHONY: all clean regenerate-data

all:
	make -C boomerang

clean:
	make -C boomerang clean

regenerate-data:
	make -C boomerang generate-data
	cp -r boomerang/generated_data .
	python transform-data.py generated_data/bijective_data.csv generated_data/symmetric_data.csv
