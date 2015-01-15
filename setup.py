from distutils.core import setup
from distutils.extension import Extension
from Cython.Distutils import build_ext
from Cython.Build.Dependencies import cythonize

setup(
    name='ptypes',
    version='0.4',
    requires=['daemon (>=1.5.5)', 'Cython (>=0.19.2)'],
    provides=['ptypes'],
    package_dir={'': 'src', 'ptypes': 'src/ptypes'},
    cmdclass={'build_ext': build_ext},
    #  One Extension per pyx file;
    # the name of the pyx file must be extensionName + ".pyx"
    ext_modules=cythonize(
        [Extension(modname,
                   ['src/'+s for s in sources]) for modname, sources in
         [("storage", ["ptypes/storage.pyx", "ptypes/md5.c"]),
          ("basetypes",  ["ptypes/basetypes.pyx"]),
          ("graph",      ["ptypes/graph.pyx"]),
          ("query",      ["ptypes/query.pyx"]),
          ("buffer",     ["ptypes/buffer.pyx"]),
          ]],
        include_dirs=['.'],
        # gdb_debug=True
    ),
)
