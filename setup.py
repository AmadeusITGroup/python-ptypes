from setuptools import setup, Extension

# Configuration to build Cython extensions
try:
    from Cython.Build import cythonize
except ImportError:
    # cython is not installed, use the .c file
    hasCython = False
    extExtention = '.c'
else:
    # cython is installed, use .pyx file
    hasCython = True
    extExtention = '.pyx'

moduleNamesAndExtraSources = [
          ("storage",       ["ptypes/md5.c"]),
          ("basetypes",     []),
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
import pprint
pprint.pprint(moduleNameAndSources)

# cythonize() checks the timestamps of Cython modules and their dependencies
# and compiles them if it detects changes. Since a source distribution 
# includes the generated .c files with time-stamps at least as recent as their
# dependencies, it will not re-cythonize during installation.
# Since cythonize() is run outside the setup() call, it will perform this 
# check on every command given to setup.py, including 'sdist'. Therefore the 
# source distribution is guaranteed to have the latest .c files.
if hasCython:
    ext_modules = cythonize(ext_modules)

with open('README.rst') as file:
    long_description = file.read()


setup(
    name='ptypes',
    version='0.4',
    author=u'Amadeus IT Group',
    author_email='opensource@amadeus.com',
#     description='',
    long_description=long_description,
    #url = "http://example.com/project/home/page/",
    #download_url = ,
    # license="Apache",
    classifiers=[
        # http://en.wikipedia.org/wiki/Software_release_life_cycle
        'Development Status :: 3 - Alpha',

        'Intended Audience :: Developers',
        'Topic :: Software Development :: Libraries',
        'Topic :: Software Development :: Libraries :: Python Modules',
        'Topic :: Scientific/Engineering',
        'Topic :: Database',
#         # Pick your license as you wish (should match "license" above)
#          'License :: OSI Approved :: Apache Software License',
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
                   #'versioneer',
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
)
