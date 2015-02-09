==============================================
Participating in the development of ``ptypes``
==============================================

What you will need
==================

.. note:: Many of the below requirements can be easily installed by
   uncommenting the appropriate lines in ``setup.py``.

Here is a list of the tools you are likely to need if you want to work on
``ptypes``:

* ``gcc``, ``gdb`` and ``make``
* ``python2.7`` (Most Linux distros include it by default. You may have to
  install the header files [usually in a package called ``python-dev`` or
  similar] on top of the normal Python2 package.)
* ``cython`` (You need at least 0.19.2. In earlier versions there is a bug that
  will make the compiled binary core. Download from
  `here <http://cython.org/#download>`_ then build and install it:
  ``cd <yourcythondir>; python setup.py build; sudo python setup.py install``)
* ``git`` (and an account on https://github.com/ so that you can send pull
  requests)
* ``pep8`` (This is a Python package to check compliance to the Python coding
  standards :pep:`8`. Install it via ``sudo apt-get install pep8``)
* ``autopep8`` (This is a package to fix non-compliant code automatically - use it
  with caution. Install is using ``sudo apt-get install python-autopep8``)
* ``setuptools``, ``virtualenv`` and ``virtualenvwrapper`` (See
  `here <http://hosseinkaz.blogspot.de/2012/06/how-to-install-virtualenv.html>`_
  how to install these.)
* ``py.test`` (``sudo apt-get install python-pytest``,
  ``sudo apt-get install python-pytest-doc``)
* `tox <https://pypi.python.org/pypi/tox>`_ (``sudo apt-get install python-tox``)
* ``valgrind`` (Use this when ``gdb`` proves to be insufficient for debugging
  memory related errors. Installation: ``sudo apt-get install valgrind``.
  You will need to download the suppression file ``Misc/valgrind-python.supp``
  from the source repository of the Python release you are using and specify
  it when running ``valgrind``.)
* `sphinx <http://sphinx-doc.org/install.html>`_
  (``sudo apt-get install python-sphinx``)

Before you make changes, have a look at :doc:`lessonsLearnt`

For a complete build-package-install-test cycle go to the directory containing
``tox.ini`` and type ``tox``. This will recompile all modules, which may
prove lengthy. For a shorter cycle, create a virtual environment called (say)
``ptypes`` (i.e. ``mkvirtualenv ptypes``) or, if it already exists, activate it
(by ``workon ptypes``), and for each cycle run ``pip install -e .; py.test``
from the directory containing ``tox.ini``.

To build the documentation, go to the ``doc`` directory and type ``make html``.

Quality guidelines
==================

Please cover new code with tests. Before submitting, run the test suites via
``tox`` and make sure they all pass. Verify that the documentation builds.

Run ``pep8`` as well. Please avoid introducing new warnings.

Coding style
============

Many of the warnings of ``pep8`` are not applicable because the verifier is
targeted at Python (as opposed to Cython) code. These warnings are silenced
in the tox.ini file.


For imports, ``cimport`` statements should precede normal imports, reflecting
the fact that a the former has a compile time effect, while the later is an
executable runtime statement.
