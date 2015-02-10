# coding=utf-8

from setuptools import setup, Extension

# Configuration to build Cython extensions
try:
    from Cython.Build import cythonize
except ImportError:
    # cython is not installed, use the .c files
    hasCython = False
    extExtention = '.c'
else:
    # cython is installed, use the .pyx files
    hasCython = True
    extExtention = '.pyx'

moduleNamesAndExtraSources = [
          ("storage",       ["ptypes/md5.c"]),
          ("graph",         []),
          ("query",         []),
          ("buffer",        []),
          ("pcollections",  []),
          ]

moduleNameAndSources = []
ext_modules = []

# One Extension per pyx file;
# the name of the pyx file must be extensionName + ".pyx"
for moduleName, extraSources in moduleNamesAndExtraSources:
    sources = ["ptypes/{}{}".format(moduleName, extExtention)]
    sources.extend(extraSources)
    moduleNameAndSources.append((moduleName, sources))
    ext_modules.append(Extension('ptypes.' + moduleName, sources))

# cythonize() checks the timestamps of Cython modules and their dependencies
# and compiles them if it detects changes. Since a source distribution 
# includes the generated .c files with time-stamps at least as recent as their
# dependencies, it will not re-cythonize during installation.
# Since cythonize() is run outside the setup() call, it will perform this 
# check on every command given to setup.py, including 'sdist'. Therefore the 
# source distribution is guaranteed to have the latest .c files.
if hasCython:
    ext_modules = cythonize(ext_modules)

with open('README.rst') as f:
    long_description = f.read()


setup(
    name='ptypes',
    version='0.5.0',

    author=u'Amadeus IT Group',
    author_email='opensource@amadeus.com',
    maintainer='Dénes Vadász',
    maintainer_email='dvadasz@amadeus.com',

    description='Persistent types: storing objects in memory-mapped files without serializing',
    long_description=long_description,
    url = "https://github.com/AmadeusITGroup/ptypes",
    download_url="https://pypi.python.org/pypi/ptypes",
    license="Apache",
    classifiers=[
        # http://en.wikipedia.org/wiki/Software_release_life_cycle
        'Development Status :: 3 - Alpha',

        'Intended Audience :: Developers',
        'Topic :: Software Development :: Libraries',
        'Topic :: Software Development :: Libraries :: Python Modules',
        'Topic :: Scientific/Engineering',
        'Topic :: Database',
        'License :: OSI Approved :: Apache Software License',
        'Operating System :: POSIX',
        'Programming Language :: Cython'
        'Programming Language :: C'
        'Programming Language :: Python :: 2',
        'Programming Language :: Python :: 2.7',
        'Programming Language :: Python :: Implementation :: CPython',
    ],
    keywords='persistency mmap',
    packages=['ptypes'],
    requires = [
                   # The below packages are required if you want to contribute
                   # to the development of ptypes. Uncomment them and
                   # run 'python setup.py develop'

                   #'Cython >=0.19.2', 
                   #'bumpversion',
                   #'tox',
                   #'pep8',
                   #'autopep8',
                   #'virtualenv',
                   #'virtualenvwrapper',
                ],
    ext_modules= ext_modules,
    tests_require=['pytest',
                   'numpy',
                   ],
    include_package_data = True,  # copy sources into the package dir for gdb
)
