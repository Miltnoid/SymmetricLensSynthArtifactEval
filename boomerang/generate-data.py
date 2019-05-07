#!/usr/local/bin/python

from __future__ import print_function
from easyprocess import EasyProcess

import os
import csv
from os.path import splitext, join
import subprocess
import sys
import time

from math import sqrt

def stddev(lst):
    mean = float(sum(lst)) / len(lst)
    return sqrt(float(reduce(lambda x, y: x + y, map(lambda x: (x - mean) ** 2, lst))) / len(lst))


TEST_EXT = '.boom'
BASELINE_EXT = '.out'
BASE_FLAGS = []
TIMEOUT_TIME = 60
STILL_WORK_TIMEOUT_TIME = 120
GENERATE_EXAMPLES_TIMEOUT_TIME = 600000

REPETITION_COUNT = 20

def ensure_dir(f):
    d = os.path.dirname(f)
    if not os.path.exists(d):
        os.makedirs(d)

def transpose(matrix):
    return zip(*matrix)

def find_tests(root):
    tests = []
    for path, dirs, files in os.walk(root):
        files = [(f[0], f[1]) for f in [splitext(f) for f in files]]
        tests.extend([(path, f[0]) for f in files if f[1] == TEST_EXT])
    return tests

def gather_datum(prog, path, base, additional_flags, timeout):
    start = time.time()
    process_output = EasyProcess([prog] + BASE_FLAGS + additional_flags + [join(path, base + TEST_EXT)]).call(timeout=timeout)
    end = time.time()
    return ((end - start), process_output.stdout,process_output.stderr)


def gather_data(rootlength, prog, path, base):
    current_data = {"Test":join(path, base).replace("_","-")[rootlength:]}

    def gather_col(flags, run_combiner, col_names, timeout_time, repetition_count):
        print(col_names)
        run_data = []
        timeout = False
        error = False
        for iteration in range(repetition_count):
    	    (time,datum,err) = gather_datum(prog, path, base,flags,timeout_time)
            if err != "":
                error = True
                break
            if time > TIMEOUT_TIME:
                timeout = True
                break
            run_data.append([time] + datum.split(","))
        if error:
            for col_name in col_names:
                current_data[col_name]=[-1]
        elif timeout:
            for col_name in col_names:
	        current_data[col_name]=[-1]
        else:
            run_data_transpose = transpose(run_data)
            for (col_name,col_val) in zip(col_names,run_combiner(run_data_transpose)):
                current_data[col_name]=col_val

    def ctime_combiner(run_data_transpose):
        print(run_data_transpose[0])
        computation_time_col = [float(x) for x in run_data_transpose[0]]
        mean = float(sum(computation_time_col) / len(computation_time_col))
        std = stddev(computation_time_col)
        return [mean,std]

    def exs_reqd_combiner(run_data_transpose):
	    example_number_col = [float(x) for x in run_data_transpose[0]]
	    return ["{:.1f}".format(sum(example_number_col)/len(example_number_col))]

    def max_exs_reqd_combiner(run_data_transpose):
	    example_number_col = [float(x) for x in run_data_transpose[0]]
	    return [int(sum(example_number_col)/len(example_number_col))]

    def specsize_combiner(run_data_transpose):
            print(run_data_transpose[1])
	    example_number_col = [float(x) for x in run_data_transpose[1]]
	    return [int(sum(example_number_col)/len(example_number_col))]


    gather_col([],ctime_combiner,["SS","SS_STD"],TIMEOUT_TIME,REPETITION_COUNT)
    gather_col(["-noCS"],ctime_combiner,["SSNC"],TIMEOUT_TIME,REPETITION_COUNT)
    gather_col(["-bijSynth"],ctime_combiner,["BS"],TIMEOUT_TIME,REPETITION_COUNT)
    gather_col(["-bijSynth","-noCS"],ctime_combiner,["BSNC"],TIMEOUT_TIME,REPETITION_COUNT)
    gather_col(["-noTerminationCondition"],ctime_combiner,["FC"],TIMEOUT_TIME,1)
    gather_col(["-dumbCost"],ctime_combiner,["NM"],TIMEOUT_TIME,1)
    gather_col(["-dumbCostCorrectPair"],ctime_combiner,["NMCC"],TIMEOUT_TIME,1)
    gather_col(["-constantCost"],ctime_combiner,["ConstCost"],TIMEOUT_TIME,1)
    gather_col(["-constantCostCorrectPair"],ctime_combiner,["ConstCostCC"],TIMEOUT_TIME,1)
    gather_col(["-noSkip"],ctime_combiner,["NoSkip"],TIMEOUT_TIME,1)
    gather_col(["-noRequire"],ctime_combiner,["NoRequire"],TIMEOUT_TIME,1)
    gather_col(["-regexSize"],specsize_combiner,["RegexSize"],TIMEOUT_TIME,1)
    gather_col(["-lensSize"],specsize_combiner,["LensSize"],TIMEOUT_TIME,1)

    return current_data

def specsize_compare(x,y):
    return int(x["SpecSize"])-int(y["SpecSize"])

def sort_data(data):
    return sorted(data,cmp=specsize_compare)

def print_data(data,fname):
    ensure_dir("generated_data/")
    with open("generated_data/" + fname + ".csv", "wb") as csvfile:
	datawriter = csv.DictWriter(csvfile,fieldnames=data[0].keys())
	datawriter.writeheader()
	datawriter.writerows(data)

def print_usage(args):
    print("Usage: {0} <prog> <test|testdir>".format(args[0]))

def transform_data(path, base, run_data):
    current_data = {"Test":join(path, base + TEST_EXT).replace("_","-")[6:]}
    run_data_transpose = transpose(run_data)
    for index in range(len(run_data_transpose)/2):
	col_name = run_data_transpose[index][0]
	col_data = run_data_transpose[index+1]
        if "" in col_data:
	    current_data[col_name]=-1
        else:
            col = [float(x) for x in col_data]
            current_data[col_name] = str(sum(col)/len(col))
    return current_data

def main(args):
    if len(args) == 4:
        prog = args[1]
        path = args[2]
        fname = args[3]
        rootlength = len(path)
        data = []
        if not os.path.exists(prog):
            print_usage(args)
        elif os.path.exists(path) and os.path.isdir(path):
            for path, base in find_tests(path):
                print(join(path, base + TEST_EXT).replace("_","-")[rootlength:])
                current_data = gather_data(rootlength,prog, path, base)
                data.append(current_data)
            #data = sort_data(data)
	    print_data(data,fname)
        else:
            path, filename = os.path.split(path)
            base, ext = splitext(filename)
            if ext != TEST_EXT:
                print_usage(args)
            else:
                data = gather_data(prog, path, base)
                sort_data(data)
		print_data([data])
    else:
        print_usage(args)

if __name__ == '__main__':
    main(sys.argv)
