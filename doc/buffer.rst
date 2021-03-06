==================
Persistent Buffers
==================


The :mod:`~ptypes.buffer` module provides extension classes for persisting any object supporting the buffer interface.

We will play with a file called :file:`testfile.mmap`.
First we make sure there is no such file::

      >>> import os
      >>> mmapFileName = '/tmp/testfile.mmap'
      >>> try: os.unlink(mmapFileName)
      ... except: pass

Now we can start the actual work and create a new storage for the persistent buffers.
First we import the necessary classes::

      >>> from ptypes.storage import Storage
      >>> from ptypes.buffer import Buffer

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         MyBuffer = self.define(Buffer)
      ...         class Root(self.schema.Structure):
      ...             myBuffer = MyBuffer
      >>> p = MyStorage(mmapFileName, fileSize=16000, stringRegistrySize=32)

      >>> s = b"This is a string."
      >>> p.root.myBuffer = p.schema.Buffer(s)
      >>> p.root.myBuffer                                             #doctest: +ELLIPSIS
      <persistent Buffer object @offset 0x...>

      >>> m = memoryview(s)
      >>> (m.format, m.itemsize, m.ndim, m.readonly, m.shape, m.strides) ==\
      ... ('B', 1, 1, True, (17,), (1,))
      True

      >>> m = memoryview(p.root.myBuffer)
      >>> (m.format, m.itemsize, m.ndim, m.readonly, m.shape, m.strides) == \
      ... ('B', 1, 1, False, (17,), (1,))
      True

      >>> m.tobytes() == b'This is a string.'
      True

      >>> del m
      >>> p.close()

      >>> p = MyStorage(mmapFileName)
      >>> m = memoryview(p.root.myBuffer)
      >>> (m.format, m.itemsize, m.ndim, m.readonly, m.shape, m.strides) ==\
      ... ('B', 1, 1, False, (17,), (1,))
      True

In Python 3 arrays expose their data over the buffer protocol. However,
there is no way to construct an array directly from an existing buffer: first
a ``memoryview`` has to be created, which can be used as a sequence initializing 
the array.

The design decision that arrays cannot be directly constructed from
a buffer is understandable in the light of arrays supporting the 
:meth:`~append()` and :meth:`~extend()` methods: these may demand the 
re-allocation of the buffer underlying the array.

In Python 2 arrays do not support the buffer protocol.::

      >>> from array import array
      >>> a=array('b', range(10))
      >>> import sys
      >>> if sys.version_info[0] == 3:
      ...     pa = p.schema.Buffer(a)     # no exception
      ...     a2 = array('b', bytes(pa))  # data is copied from the persistent buffer
      ...     assert a == a2
      ...     assert a is not a2
      ...     del pa
      ... else: 
      ...     try: p.schema.Buffer(a)
      ...     except TypeError as e: 
      ...         assert e.message == "Objects of type 'array' do not support the buffer protocol." 
      ...     else:
      ...         assert False, "dead code"

      >>> m.tobytes() == b'This is a string.'
      True
      >>> del m
      >>> p.close()

      >>> import numpy as np
      >>> a = np.random.rand(1,2,3) #random values in shape (1,2,3)
      >>> p = MyStorage(mmapFileName)

Let's copy ``a`` into the persistent storage::

      >>> p.root.myBuffer = p.schema.Buffer(a)
      >>> p.close()
      >>> p = MyStorage(mmapFileName)

:func:`np.asarray() <numpy.asarray>` creates an array without copying the data again::

      >>> b = np.asarray(p.root.myBuffer)
      >>> np.all( a == b )
      True
      >>> p.close()                                          #doctest: +ELLIPSIS
      Traceback (most recent call last):
       ...
      ValueError: Cannot close <MyStorage '/tmp/testfile.mmap'> - some proxies are still around: <persistent Buffer object @offset ...>

``b`` still refers to ``p.root.myBuffer`` so we cannot close the storage.
(If it were possible to close the storage while ``b`` is around, the memory
where ``b`` keeps its data would be unmapped, so accessing it through the methods
of ``b`` would result in a segmentation fault.)::

      >>> del b

Now it's fine to close it::

      >>> p.close()
