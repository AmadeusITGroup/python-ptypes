==================
Persistent buffers
==================


The ``buffer`` module provides extension classes for persisting any object supporting the buffer interface.

We will play with a file called ``testfile.mmap``. First we make sure there is no such file:
 
      >>> import os
      >>> mmapFileName = '/home/dvadasz/testfile.mmap'
      >>> try: os.unlink(mmapFileName)
      ... except: pass

Now we can start the actual work and create a new storage for the persistent buffers.
First we import the necessary classes:
 
      >>> from storage import Storage, Structure, StructureMeta
      >>> from buffer import Buffer
      
      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         MyBuffer = self.define( Buffer )
      ...         class Root(Structure):  
      ...             __metaclass__ = StructureMeta
      ...             myBuffer = MyBuffer
      >>> p = MyStorage(mmapFileName, fileSize=16000, stringRegistrySize=32)   
      
      >>> s = "This is a string."
      >>> p.root.myBuffer = p.schema.Buffer(s)
      >>> p.root.myBuffer                                             #doctest: +ELLIPSIS
      <persistent Buffer object @offset 0x...L>
      
      >>> m = memoryview(s)
      >>> m.format, m.itemsize, m.ndim, m.readonly, m.shape, m.strides 
      ('B', 1L, 1L, True, (17L,), (1L,))
      
      >>> m = memoryview(p.root.myBuffer)
      >>> m.format, m.itemsize, m.ndim, m.readonly, m.shape, m.strides 
      ('B', 1L, 1L, False, (17L,), (1L,))
      
      >>> m.tobytes()
      'This is a string.'
      
      >>> del m
      >>> p.close()
      
      >>> p = MyStorage(mmapFileName)   
      >>> m = memoryview(p.root.myBuffer)
      >>> m.format, m.itemsize, m.ndim, m.readonly, m.shape, m.strides 
      ('B', 1L, 1L, False, (17L,), (1L,))
      
      >>> from array import array
      >>> a=array('b', range(10))
      >>> p.schema.Buffer(a)                                             #doctest: +ELLIPSIS
      Traceback (most recent call last):
       ...
      TypeError: Objects of type 'array' does not support the buffer protocol.
      
      >>> m.tobytes()
      'This is a string.'
      >>> del m
      >>> p.close()
      
