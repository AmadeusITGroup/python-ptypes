.. ptypes documentation master file, created by
   sphinx-quickstart on Thu Dec  4 12:19:59 2014.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Welcome to the documentation of the ``ptypes`` project!
=======================================================

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
of its API and the completeness of its functionality. 
In particular it does not support multi-threading or 
multi-processing and there is **no guarantee** on

* the stability of its API
* the portability of the data stored with it
* the evolvability of the schema of the data
* the atomicity of updates in the presence of failures.


Contents:
---------

.. toctree::
   :maxdepth: 2

   installation
   examples
   reference
   contributing/contributorsGuide
   roadmap

Indices and tables
------------------

* :ref:`genindex`
* :ref:`modindex`
* :ref:`search`

