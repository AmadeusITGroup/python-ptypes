======================
Welcome to ``ptypes``!
======================

The ``ptypes`` ("persistent types") package is a set of Python extension
modules written in `Cython <http://cython.org/>`_. 
It provides a persistency mechanism to `Python <http://www.python.org/>`_
programs based on memory mapped files. ``ptypes`` emphasises execution
speed. The persistent objects (persistent versions of ints, floats, strings, 
structures, lists, sets, dicts plus any extension type supporting the
`buffer interface <https://docs.python.org/2.7/c-api/buffer.html>`_) can be 
accessed and manipulated directly, without serializing and de-serializing them.

The package also implements data types for property graphs (nodes and
edges), as well as a basic query interface allowing the enumeration of 
object-tuples matching a given pattern at (nearly) the speed of a C program.

In its current shape, ``ptypes`` is experimental with regards to the stability 
of its API and the completeness of its functionality. Making the updates to 
the memory mapped files 
`atomic <http://en.wikipedia.org/wiki/Atomicity_%28database_systems%29>`_ and
implementing garbage collection for the persistent objects are of prime 
priorities. 

Installation
------------

``ptypes`` is tested on Linux (but should run on any Posix platform) using 
CPython 2.7 (Python 3 support is on the agenda). It is distributed as a source 
tarball, so you need to have ``gcc`` to install it. The simplest way to do so 
is::

    pip install ptypes

If you do not have internet access on the host where you need to install it, 
then download it from `PyPI <https://pypi.python.org/pypi/ptypes>`_ on a host 
where you do have internet access, copy the tarball over to the target host 
and::

    tar -xf ptypes-<version>.tgz
    cd ptypes-<version>
    python setup.py install

In the ``doc`` directory you should find abundant examples of how to use it.