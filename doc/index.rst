.. ptypes documentation master file, created by
   sphinx-quickstart on Thu Dec  4 12:19:59 2014.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

Welcome to the documentation of the ``ptypes`` project!
=======================================================

Ptypes is an extension module written in Cython to provide 
an efficient persistency solution to Python based on memory mapped files.

We beleive that on the long term it has the potential to evolve into an 
efficient multi-core programing platform for CPython, working around the 
problem posed by the  GIL.

In its current state ``ptypes`` is highly experimental with a bunch of missing
features. In particular it does not support multi-threading or 
multi-processing and there is no guarantee on

* the stability of its API
* the portability of the data stored with it
* the evolvability of the schema of the data
* the atomicity of updates in the presence of failures.

Its potentials are high though, so you are wellcome to participate!

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

