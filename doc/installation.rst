============
Installation
============

Prerequisites
-------------

* A POSIX-compliant operating system (ptypes is developed and tested on Linux)
* CPython 2.7 (Python 3 support is on the agenda)
* ``gcc``

Installation from the source tarball
------------------------------------

The simplest way is::

    pip install ptypes

If you do not have internet access on the host where you need to install it,
then download it from `PyPI <https://pypi.python.org/pypi/ptypes>`_ on a host
where you do have internet access, copy the tarball over to the target host
and::

    tar -xf ptypes-<version>.tgz
    cd ptypes-<version>
    python setup.py install

