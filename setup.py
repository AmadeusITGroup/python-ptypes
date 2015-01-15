from distutils.core import setup
from distutils.extension import Extension
from Cython.Distutils import build_ext
from Cython.Build.Dependencies import cythonize

from setuptools import find_packages

setup(
    name='ptypes',
    version='0.4',
    author=u'Amadeus IT Group',
    author_email='opensource@amadeus.com',
    requires=['Cython (>=0.19.2)'],
    # packages=['ptypes'],
    packages=find_packages(),
    cmdclass={'build_ext': build_ext},
    #  One Extension per pyx file;
    # the name of the pyx file must be extensionName + ".pyx"
    ext_modules=cythonize(
        [Extension('ptypes.' + modname,
                   [s for s in sources]) for modname, sources in
         [("storage", ["ptypes/storage.pyx", "ptypes/md5.c"]),
          ("basetypes",  ["ptypes/basetypes.pyx"]),
          ("graph",      ["ptypes/graph.pyx"]),
          ("query",      ["ptypes/query.pyx"]),
          ("buffer",     ["ptypes/buffer.pyx"]),
          ("pcollections",     ["ptypes/pcollections.pyx"]),
          ]],
    ),
    tests_require=[
        'pytest',
        'numpy',
    ],
)
