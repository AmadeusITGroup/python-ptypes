===============================
Getting Started with ``ptypes``
===============================

This page will introduce the usage of the :mod:`ptypes` module through a few basic examples.
We will play with a file called :file:`testfile.mmap`.
First we make sure there is no such file::

      >>> import os
      >>> mmapFileName = '/tmp/testfile.mmap'
      >>> try: os.unlink(mmapFileName)
      ... except: pass

Now we can start the actual work and create a new storage with a very simple structure.
First we import the necessary classes::

   >>> from ptypes.storage import Storage

The :class:`~ptypes.storage.Storage` class represents a persistent data store.
To make it actually usable, we have to subclass it and override its
:meth:`~ptypes.storage.Storage.populateSchema()` callback method with code
defining the structure of our persistent store.

<<<<<<< HEAD
The structure is defined in the
:meth:`~ptypes.storage.Storage.populateSchema()` method by creating a class

 * called ``Root`` 
 * subclassed from ``self.schema.Structure`` (where ``self`` is the sole
parameter of :meth:`~ptypes.storage.Storage.populateSchema()`)

``self.schema.Structure`` comes with a metaclass (:class:`~ptypes.storage.StructureMeta`),
which takes care of binding the persistent class to the
:class:`~ptypes.storage.Storage`` instance.
This way there is no need to pass the :class:`~ptypes.storage.Storage` instance
to the constructor when creating persistent instances::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         class Root(self.schema.Structure):
      ...             pass

Now we are ready to create our first persistent storage object.
The :meth:`~ptypes.storage.Storage.populateSchema()` callback will be invoked
automatically if and when the schema of a new storage object needs to be
created. The reason for having to define the structure of the storage inside a
callback is that the persistent types describing the structure are bound to the
storage instance.
This way we avoid having to refer explicitely to the storage instance through
the code that manipulates persistent objects inside the storage::

      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)

There we go! We created our first persistent storage. The ``fileSize`` keyword
argument specifies the size of the files in bytes and it is rounded up to the
nearest multiple of the page size.
The ``stringRegistrySize`` parameter is the number of interned strings the
storage can hold.  Upon the first access to the ``root`` attribute of the
storage an instance of the ``Root`` class is created and returned::

      >>> p.root                                             #doctest: +ELLIPSIS
      <persistent Root object @offset 0x...L>

So far so good, but our storage is not very useful as it cannot hold any data:
the root object has no attributes.
Let's add some fields to our ``Root`` class.
To do so, we need to specify a persistent type for each field.  The available
persistent types are accessible as attributes on the module object representing
the *schema* of the storage::

      >>> p.schema
      <module 'schema' (built-in)>
      >>> sorted(dir(p.schema))
      ['Float', 'Int', 'Root', 'String', 'Structure', '__doc__', '__name__']

It is essential that before we lose the reference to a storage object we
:meth:`~ptypes.storage.Storage.close()` it, otherwise the underlying file
remains open (occupying disk space even if deleted) and mapped into memory
(wasting the address space)::

      >>> p.close()

Now here is an improved version of our storage, this time with the structure
having some useful fields::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         print 'Creating an improved schema...'
      ...         class Root(self.schema.Structure):
      ...             name = self.schema.String
      ...             age = self.schema.Int
      ...             weight = self.schema.Float
      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)

Oops, we expected a message ``Creating an improved schema...``, why didn't we get it?
Because the file under the storage has already been created and properly
initialized (with the useless version of ``Root``.)
The :meth:`~ptypes.storage.Storage.populateSchema()` method is only called once
on a file.
On subsequent attachment attempts the schema is read back from the storage.

So let's get rid of the old storage and create a new one::

      >>> p.close()
      >>> del p
      >>> os.unlink(mmapFileName)
      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)
      Creating an improved schema...

Now we have our improved storage, with an instance of ``Root`` created but
still un-initialized::

      >>> p.root.name is None
      True
      >>> p.root.age                                                 #doctest: +ELLIPSIS
      <persistent Int object '0' @offset 0x...>
      >>> p.root.weight                                               #doctest: +ELLIPSIS
      <persistent Float object '0.0' @offset 0x...>
 
Let's try to initialize it!::

      >>> p.root.age = 27
      >>> p.root.weight = 73.1415926

The Python integer and float assigned are stored by value. When accessing them, we get
proxy objects back, allowing for various operations on them.
To get the original Python integer back, you have to access the
:attr:`~ptypes.storage.Structure.contents`` attribute of the proxy::

      >>> p.root.age, p.root.age.contents                             #doctest: +ELLIPSIS
      (<persistent Int object '27' @offset 0x...>, 27)
      >>> p.root.weight, p.root.weight.contents                       #doctest: +ELLIPSIS
      (<persistent Float object '73.1415926' @offset 0x...>, 73.1415926)

*... and a year later James put on some weight ;-)* ::

      >>> p.root.age.inc()
      >>> p.root.weight.add(31.45)
      >>> p.root.age.contents, p.root.weight.contents
      (28, 104.5915926)
 
The :class:`~ptypes.Storage.Int` and :class:`~ptypes.storage.Float` persistent
types are assigned by value because it takes less memory to store them directly
than to create :class:`~ptypes.storage.Int` or :class:`~ptypes.storage.Float`
objects and store offsets to those.
The downside of this decision is that one cannot instanciate these objects
directly::

      >>> i = p.schema.Int(3)                                      #doctest: +ELLIPSIS +REPORT_NDIFF
      Traceback (most recent call last):
        ...
      TypeError: <persistent class 'Int'> exhibits store-by-value semantics and therefore can only be instantiated inside a container (e.g. in Structure)

Types assigned by value can only be created as part of an other object containing them.
When the container is created, the space allocated for it includes the space for the 
assigned-by-value types. The proxy objects or their
:attr:`~ptypes.storage.Structure.`contents` descriptor can be used to read or
write their contents, but there is neither a need nor a way to create
assigned-by-value instances in a stand-alone fashion.

In contrast to :class:`~ptypes.storage.Int` and :class:`~ptypes.storage.Float`,
persistent strings are assigned by reference.
The assignment to a field will convert a Python string implicitly to a persistent string::

      >>> p.root.name = 'James Bond'
      >>> p.root.name                                                 #doctest: +ELLIPSIS
      <persistent String object 'James Bond' @offset 0x...>

We got back the persistent string; if we want it as a Python string object, we
access its :attr:`~ptypes.storage.Structure.`contents` attribute::

      >>> p.root.name.contents
      'James Bond'

Or alternatively::

      >>> str(p.root.name)
      'James Bond'

The assignment of the Python string  works because the constructor of
``p.schema.String`` accepts a Python string as its single argument.
Note however, that this solution leaks persistent storage space, as each time
the Python string ``'James Bond'`` is  assigned,
a new persistent string is allocated, storing the same sequence of characters::

      >>> p.root.name.isSameAs(p.schema.String('James Bond'))
      False
      >>> p.root.name == p.schema.String('James Bond')
      True

To remedy this, the recommended way of interning strings is via the *string
registry* of the storage::

      >>> p.root.name = p.stringRegistry.get('James Bond')

This always returns proxy objects to the same persistent string::

      >>> p.root.name == p.stringRegistry.get('James Bond')
      True

Although the proxy objects are not the same::

      >>> p.root.name is p.stringRegistry.get('James Bond')
      False

This is just like with the Python strings::

      >>> p.root.name.contents == p.schema.String('James Bond').contents
      True
      >>> p.root.name.contents is p.schema.String('James Bond').contents
      False

From an already existing file a storage can be created without specifying the
size parameters or a schema. Its contents is preserved::

      >>> p.close()

      >>> p = Storage(mmapFileName)
      >>> p.root #doctest: +ELLIPSIS
      <persistent Root object @offset 0x...L>
      >>> p.root.name.contents
      'James Bond'
      >>> p.close()
      >>> os.unlink(mmapFileName)

Our improved storage structure is still not very usefull as we can only define a single
secret agent in it. What if we have more?

When defining the structure, we can rely on the ``type descriptor classes``. With the help of
these one can define persistent types parametrized with already existing persistent types.
The most notable type descriptors are Dict and List.
To define a parametrized persistent type, one instantiates a type descriptor supplying the
desired name of the new persistent type. The parameters of the type have to be specified
using the item access operator, which records the parameters and returns the type descriptor
instance. The instance is then passed in to the
:meth:`~ptypes.storage.Storage.define()` method of the :class:`~ptypes.storage.Storage`,
which will actually create the new persistent type. Let's see this through an example::

      >>> from ptypes.storage import Dict, List
      >>> class MyStorage(Storage):
      ...
      ...     def populateSchema(self):
      ...
      ...         class Agent(self.schema.Structure):
      ...             name = self.schema.String
      ...             age = self.schema.Int
      ...             weight = self.schema.Float
      ...
      ...         self.define(List('ListOfAgents')[Agent])
      ...         self.define(Dict('AgentsByName')[self.schema.String, Agent])
      ...
      ...         class Root(self.schema.Structure):
      ...             agents = self.schema.ListOfAgents
      ...             agentsByName = self.schema.AgentsByName

      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)

Before we access the persistent list or dict, we need to create them::

      >>> p.root.agents = p.schema.ListOfAgents()
      >>> p.root.agentsByName = p.schema.AgentsByName(size=13)

Now we can store at least 13 agents by their names and ages (the actual limits
may be higher).
Note that while the root object was created automatically on the first access to ``p.root``,
all other :class:`~ptypes.storage.Structure` instances have to be created
explicitly. Specifying keyword arguments as constructor parameters allows for
the immediate initialization of the fields of the structure::

      >>> for agentName, age in (("Felix Leiter", 31), ("Miss Moneypenny", 23), ("Bill Tanner",57)):
      ...     agent = p.schema.Agent(name=p.stringRegistry.get(agentName), age=age )
      ...     p.root.agents.append(agent)
      ...     p.root.agentsByName[agent.name] = agent
      >>> for agent in p.root.agents:
      ...     print agent.name
      Felix Leiter
      Miss Moneypenny
      Bill Tanner

Note that in the ``print`` statements above the persistent string got implicitly converted
to a Python string via ``str()``. When the persistent string is the return value of an
expression typed in at the interpreter prompt, ``repr()`` is invoked; that is why you
got different representations of persistent strings in the previous examples.

The persistent Dicts support :meth:`~ptypes.storage.Dict.iteritems()`,
:meth:`~ptypes.storage.Dict.iterkeys()` and :meth:`~ptypes.storage.Dict.itervalues()`::

      >>> for key, value in p.root.agentsByName.iteritems():
      ...     print key, value                                    #doctest: +ELLIPSIS
      Felix Leiter <persistent Agent object @offset 0x...>
      Bill Tanner <persistent Agent object @offset 0x...>
      Miss Moneypenny <persistent Agent object @offset 0x...>
      >>> print [key.contents for key in p.root.agentsByName.iterkeys()]
      ['Felix Leiter', 'Bill Tanner', 'Miss Moneypenny']
      >>> print [agent.name.contents for agent in p.root.agentsByName.itervalues()]
      ['Felix Leiter', 'Bill Tanner', 'Miss Moneypenny']

For persistent sets only :meth:`~ptypes.storage.Set.iterkeys()` is supported::

      >>> for _ in p.stringRegistry.itervalues(): pass                    #doctest: +ELLIPSIS
      Traceback (most recent call last):
      ...
      TypeError: Cannot iterate over the values: no value class is defined. (Is this not a Set?)
      >>> for _ in p.stringRegistry.iteritems(): pass                    #doctest: +ELLIPSIS
      Traceback (most recent call last):
      ...
      TypeError: Cannot iterate over the items: no value class is defined. (Is this not a Set?)

The dictionary accepts non-persistent keys to look up values, as long as it was
defined with a key class that accpets the non-persistent key as its sole
constructor argument::

      >>> p.root.agentsByName["Miss Moneypenny"].weight = 57.3                #doctest: +ELLIPSIS
      >>> for agent in p.root.agents:
      ...     print agent.weight.contents,
      0.0 57.3 0.0

Now let's finish with this storage and create a new one to demonstrate how Dict
and List work with types assigned by value::

      >>> p.close()                                                             #doctest: +ELLIPSIS
      Traceback (most recent call last):
      ...
      ValueError: Cannot close <MyStorage '...'> - some proxies are still around: <persistent Agent object @offset 0x...L> <persistent String object 'Miss Moneypenny' @offset 0x...L> <persistent Agent object @offset 0x...L>

Ooops... Indeed, the ``key``, ``value`` and ``agent`` references from the
previous examples are still around, and if we closed the storage (which unmaps
the underlying file), the pointers into the mapped memory area in these proxy
objects would become invalid. Trying to use these objects with the dangling
pointers would cause segmentation faults.
Therefore, all the references to proxy objects belonging to the storage (except
the reference of the storage object to the root, in our example ``p.root``)
must be deleted before closing the storage::

      >>> del key, value, agent
      >>> p.close()

Accessing the root property after closing the storage or trying to close it
again will raise a ValueError exception::

      >>> p.root                                               #doctest: +ELLIPSIS
      Traceback (most recent call last):
       ...
      ValueError: Storage ... is closed.

      >>> p.close()                                                #doctest: +ELLIPSIS
      Traceback (most recent call last):
       ...
      ValueError: Storage ... is closed.
      >>> os.unlink(mmapFileName)

Now we really can continue and demonstrate that the
:class:`~ptypes.storage.Dict` and :class:`~ptypes.storage.List` type
descriptors work just as well with types assigned by value::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         self.define(List('ListOfInts' )[self.schema.Int ])
      ...         self.define(List('ListOfFloats')[self.schema.Float])
      ...
      ...         class Root(self.schema.Structure):
      ...             uints = self.schema.ListOfInts
      ...             floats = self.schema.ListOfFloats
      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)      #doctest: +ELLIPSIS
      >>> p.root.uints = p.schema.ListOfInts()
      >>> p.root.floats = p.schema.ListOfFloats()
      >>> from random import seed, random
      >>> seed(13)
      >>> for i in range(10):
      ...    p.root.uints.append(i)
      ...    p.root.floats.append(random())
      >>> for i in p.root.uints:
      ...      print i.contents,
      0 1 2 3 4 5 6 7 8 9
      >>> for f in p.root.floats:
      ...      print f.contents,
      0.259008491715 0.685257992965 0.684081918016 0.84933616139 0.185724173874 0.230558608965 0.147159918168 0.225162935562 0.734023602213 0.13021302276
      >>> del i, f
      >>> p.close()
      >>> os.unlink(mmapFileName)

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         self.define(Dict('MyType')[self.schema.Int, self.schema.String])
      ...
      ...         class Root(self.schema.Structure):
      ...             myType = self.schema.MyType
      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)      #doctest: +ELLIPSIS  +REPORT_NDIFF
      >>> os.unlink(mmapFileName)

If you pass in the wrong number of type arguments to a type descriptor, you
will get a :exc:`ValueError` exception::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         self.define(Dict('BadType')[1, 2, 3])
      ...         class Root(self.schema.Structure):
      ...             pass
      >>> p = MyStorage(mmapFileName, 1, 32)                                  #doctest: +ELLIPSIS
      Traceback (most recent call last):
         ...
      TypeError: Type BadType must have at most 2 parameter(s), found (1, 2, 3)

      >>> os.unlink(mmapFileName)
      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         self.define(Dict('BadType')[None, None])
      ...         class Root(self.schema.Structure):
      ...             pass
      >>> p = MyStorage(mmapFileName, 1, 32) #doctest: +ELLIPSIS
      Traceback (most recent call last):
         ...
      TypeError: The type parameter specifying the type of keys cannot be None

If you pass in ``None`` as the value class to a :class:`~ptypes.storage.Dict`,
you get set-like behaviour.
For convenience, :class:`~ptypes.storage.Set` is defined exactly that way.
The below example also demonstrates that :meth:`~ptypes.storage.Storage.define()`
returns the defined type instance, so you can use it in subsequent type
definitions::

      >>> os.unlink(mmapFileName)
      >>> from ptypes.storage import Set
      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         stringSet1 = self.define(Dict('ThisIsInFactASet')[self.schema.String, None])
      ...         stringSet2 = self.define(Set('ThisIsAnotherSet')[self.schema.String])
      ...         class Root(self.schema.Structure):
      ...             strings1 = stringSet1
      ...             strings2 = stringSet2
      >>> p = MyStorage(mmapFileName, 1, 32)                      
      >>> p.root.strings1 = p.schema.ThisIsInFactASet(13)
      >>> s1 = p.root.strings1.get('abc\x00def')
      >>> s1                                                        #doctest: +ELLIPSIS
      <persistent String object 'abc\x00def' @offset 0x...L>
      >>> s1.contents
      'abc\x00def'

Note that type definitions are not interchangable, even if they come from the same type
descriptor with the same parameters::

      >>> p.root.strings2 = p.schema.ThisIsInFactASet(13)
      Traceback (most recent call last):
         ...
      TypeError: Expected <persistent class 'ThisIsAnotherSet'>, found <persistent class 'ThisIsInFactASet'>
      >>> del s1
      >>> p.close()
      >>> os.unlink(mmapFileName)

The :meth:`~ptypes.storage.Storage.define()` method will complain if you try to
pass in some garbage::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         self.define( 'foo' )
      >>> p = MyStorage(mmapFileName, 1, 32) #doctest: +ELLIPSIS
      Traceback (most recent call last):
         ...
      TypeError: Don't know how to define 'foo'

      >>> os.unlink(mmapFileName)

That's it for getting started!
