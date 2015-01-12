#!/usr/bin/python
""" A utility to set up pyximport and run the doctests in one or more modules
"""
import doctest
import sys

import logging
logging.basicConfig(level='DEBUG')
import pyximport
pyximport.install(build_in_temp=False, setup_args={'include_dirs':'../src/ptypes'}) #doctest: +ELLIPSIS
sys.path.append('src/ptypes')
sys.path.append('src')
sys.path.append('../src/ptypes')
sys.path.append('../src')

for testfile in sys.argv[1:]:
    doctest.testfile(testfile,  module_relative=False)
