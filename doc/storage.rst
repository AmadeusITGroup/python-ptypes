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
This way we avoid having to refer explicitly to the storage instance through
the code that manipulates persistent objects inside the storage::

      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)

There we go! We created our first persistent storage. The ``fileSize`` keyword
argument specifies the size of the files in bytes and it is rounded up to the
nearest multiple of the page size.
The ``stringRegistrySize`` parameter is the number of interned strings the
storage can hold.  Upon the first access to the ``root`` attribute of the
storage an instance of the ``Root`` class is created and returned::

      >>> p.root                                           #doctest: +ELLIPSIS
      <persistent Root object @offset 0x...>

So far so good, but our storage is not very useful as it cannot hold any data:
the root object has no attributes.
Let's add some fields to our ``Root`` class.
To do so, we need to specify a persistent type for each field.  The available
persistent types are accessible as attributes on the module object representing
the *schema* of the storage::

      >>> p.schema                                          #doctest: +ELLIPSIS
      <module 'schema'...>
      >>> [x for x in dir(p.schema) if not x.startswith('__')]
      ['ByteString', 'Float', 'Int', 'Root', 'Structure']

It is essential that before we lose the reference to a storage object we
:meth:`~ptypes.storage.Storage.close()` it, otherwise the underlying file
remains open (occupying disk space even if deleted) and mapped into memory
(wasting the address space)::

      >>> p.close()

Now here is an improved version of our storage, this time with the structure
having some useful fields::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         print('Creating an improved schema...')
      ...         class Root(self.schema.Structure):
      ...             name = self.schema.ByteString
      ...             age = self.schema.Int
      ...             weight = self.schema.Float
      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)

Oops, we expected a message ``Creating an improved schema...``, why didn't we
get it? Because the file under the storage has already been created and
properly initialized (with the useless version of ``Root``.)
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

      >>> p.root.name = b'James Bond'
      >>> p.root.name                                                 #doctest: +ELLIPSIS
      <persistent ByteString object ...'James Bond' @offset 0x...>

We got back the persistent string; if we want it as a Python byte string object, we
access its :attr:`~ptypes.storage.Structure.`contents` attribute::

      >>> p.root.name.contents == b'James Bond'
      True

Note that converting the persistent byte string to a string is possible, ::

      >>> str(p.root.name)
      'James Bond'

The assignment of the Python string works because the constructor of
``p.schema.ByteString`` accepts a Python byte string as its single argument.
Note however, that this solution leaks persistent storage space, as each time
the Python string ``'James Bond'`` is  assigned,
a new persistent string is allocated, storing the same sequence of characters::

      >>> p.root.name.isSameAs(p.schema.ByteString(b'James Bond'))
      False
      >>> p.root.name == p.schema.ByteString(b'James Bond')
      True

To remedy this, the recommended way of interning strings is via the *string
registry* of the storage::

      >>> p.root.name = p.stringRegistry.get(b'James Bond')

This always returns proxy objects to the same persistent string::

      >>> p.root.name == p.stringRegistry.get(b'James Bond')
      True

Although the proxy objects are not the same::

      >>> p.root.name is p.stringRegistry.get(b'James Bond')
      False

This is just like with the Python strings::

      >>> p.root.name.contents == p.schema.ByteString(b'James Bond').contents
      True
      >>> p.root.name.contents is p.schema.ByteString(b'James Bond').contents
      False

From an already existing file a storage can be created without specifying the
size parameters or a schema. Its contents is preserved::

      >>> p.close()

      >>> p = Storage(mmapFileName)
      >>> p.root #doctest: +ELLIPSIS
      <persistent Root object @offset 0x...>
      >>> print(p.root.name.contents.decode())
      James Bond
      >>> p.close()
      >>> os.unlink(mmapFileName)

Our improved storage structure is still not very useful as we can only define a single
secret agent in it. What if we have more?

When defining the structure, we can rely on the ``type descriptor classes``. With the help of
these one can define persistent types parameterized with already existing persistent types.
The most notable type descriptors are Dict and List.
To define a parameterized persistent type, one instantiates a type descriptor supplying the
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
      ...             name = self.schema.ByteString
      ...             age = self.schema.Int
      ...             weight = self.schema.Float
      ...
      ...         self.define(List('ListOfAgents')[Agent])
      ...         self.define(Dict('AgentsByName')[self.schema.ByteString, Agent])
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

      >>> for agentName, age in ((b"Felix Leiter", 31), (b"Miss Moneypenny", 23), (b"Bill Tanner",57)):
      ...     agent = p.schema.Agent(name=p.stringRegistry.get(agentName), age=age )
      ...     p.root.agents.append(agent)
      ...     p.root.agentsByName[agent.name] = agent
      >>> for agent in p.root.agents:
      ...     print(agent.name)
      Felix Leiter
      Miss Moneypenny
      Bill Tanner

Note that in the ``print`` statements above the persistent string got implicitly converted
to a Python string via ``str()``. When the persistent string is the return value of an
expression typed in at the interpreter prompt, ``repr()`` is invoked; that is why you
got different representations of persistent strings in the previous examples.

The persistent Dicts support :meth:`~ptypes.storage.Dict.iteritems()`,
:meth:`~ptypes.storage.Dict.iterkeys()` and :meth:`~ptypes.storage.Dict.itervalues()`::

      >>> print('\n'.join(sorted(["{} {}".format(key, value) for key, value in p.root.agentsByName.iteritems()])))                           #doctest: +ELLIPSIS
      Bill Tanner <persistent Agent object @offset 0x...>
      Felix Leiter <persistent Agent object @offset 0x...>
      Miss Moneypenny <persistent Agent object @offset 0x...>
      >>> sorted([key.contents for key in p.root.agentsByName.iterkeys()]) == \
      ... [b'Bill Tanner', b'Felix Leiter', b'Miss Moneypenny']
      True
      >>> sorted([agent.name.contents for agent in p.root.agentsByName.itervalues()]) == \
      ... [b'Bill Tanner', b'Felix Leiter', b'Miss Moneypenny']
      True

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

      >>> p.root.agentsByName[b"Miss Moneypenny"].weight = 57.3                #doctest: +ELLIPSIS
      >>> for agent in p.root.agents:
      ...     print(agent.weight.contents)
      0.0
      57.3
      0.0

Now let's finish with this storage and create a new one to demonstrate how Dict
and List work with types assigned by value::

      >>> p.close()                                                             #doctest: +ELLIPSIS
      Traceback (most recent call last):
      ...
      ValueError: Cannot close <MyStorage '...'> - some proxies are still around: <persistent Agent object @offset 0x...>

Ooops... Indeed, the ``key``, ``value`` and ``agent`` references from the
previous examples are still around, and if we closed the storage (which unmaps
the underlying file), the pointers into the mapped memory area in these proxy
objects would become invalid. Trying to use these objects with the dangling
pointers would cause segmentation faults.
Therefore, all the references to proxy objects belonging to the storage (except
the reference of the storage object to the root, in our example ``p.root``)
must be deleted before closing the storage::

      >>> key = value = agent = None
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
      ...      print(i.contents)
      0
      1
      2
      3
      4
      5
      6
      7
      8
      9
      >>> for f in p.root.floats:                           #doctest: +ELLIPSIS
      ...      print(f.contents)
      0.25900849171...
      0.68525799296...
      0.68408191801...
      0.8493361613...
      0.18572417387...
      0.23055860896...
      0.14715991816...
      0.22516293556...
      0.73402360221...
      0.1302130227...
      >>> del i, f
      >>> p.close()
      >>> os.unlink(mmapFileName)

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         self.define(Dict('MyType')[self.schema.Int, self.schema.ByteString])
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
      ...         stringSet1 = self.define(Dict('ThisIsInFactASet')[self.schema.ByteString, None])
      ...         stringSet2 = self.define(Set('ThisIsAnotherSet')[self.schema.ByteString])
      ...         class Root(self.schema.Structure):
      ...             strings1 = stringSet1
      ...             strings2 = stringSet2
      >>> p = MyStorage(mmapFileName, 1, 32)                      
      >>> p.root.strings1 = p.schema.ThisIsInFactASet(13)
      >>> s1 = p.root.strings1.get(b'abc\x00def')
      >>> s1                                                #doctest: +ELLIPSIS
      <persistent ByteString object 'abc...def' @offset 0x...>

      Note that in the above between 'abc' and 'def' the null 
      character is displayed according to the encoding of your terminal

      >>> s1.contents == b'abc\x00def'
      True

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
      >>> p = MyStorage(mmapFileName, 1, 32)              #doctest: +ELLIPSIS
      Traceback (most recent call last):
         ...
      TypeError: Don't know how to define 'foo'

      >>> os.unlink(mmapFileName)

The next step in improving the schema of our storage could be do define some
methods on the ``Root`` class. However, ``ptypes`` does not support the
definition of methods directly in the class definining a persistent structure::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         class Root(self.schema.Structure):
      ...             def foo(self): pass

      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)  #doctest: +ELLIPSIS
      Traceback (most recent call last):
         ...
      TypeError: 'foo' is defined as a non-pickleable volatile member <function ...foo at ...> in a persistent structure
      >>> os.unlink(mmapFileName)

This restriction does not mean a persistent structure cannot have methods (or 
other non-pickleable members) at all: it can inherit them from its volatile 
base classes.

The reason for this restriction is not a merely technical one (the lack of 
pickleability could be worked around). The class defining the persistent
structure becomes meta-data, without which the data of the storage would be
inaccessible. Therefor it is saved in the storage and once saved, it is
immutable. Were methods defined there, they would also become immutable,
or in other words unmaintainable.

.. inheritance-and-persistent-structures:

Inheritance and persistent structures
--------------------------------------

Already existing pesristent structures can be used as base classes when 
defining a new one. Volatile classes can also be among the bases::

      >>> from testHelpers import VolatileMixIn, VolatileBase
      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         class Base(self.schema.Structure, VolatileMixIn):
      ...             name = self.schema.ByteString
      ...             age = self.schema.Int
      ...         VolatileBase.bar = self.schema.ByteString    # ignored
      ...         class Root(Base, VolatileBase):
      ...             name = self.schema.ByteString
      ...             weight = self.schema.Float

      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)
      >>> p.root.name is None
      True
      >>> p.root.age                                                 #doctest: +ELLIPSIS
      <persistent Int object '0' @offset 0x...>
      >>> p.root.weight                                               #doctest: +ELLIPSIS
      <persistent Float object '0.0' @offset 0x...>
      >>> p.root.foo()
      314
      
Note that persistent fields defined in volatile base classes are ignored (i.e. 
the class attribute remains a reference to a persistent type as opposed
to converting it to a persistent field) and a warning is given about this::

      >>> p.root.bar
      <persistent class 'ByteString'>

When an existing storage is re-opened, the methods of the volatile mix-in are 
restored from the module defining the mix-in::

      >>> p.close()
      >>> p = MyStorage(mmapFileName)
      >>> p.root.foo()
      314
      >>> p.close()
      >>> os.unlink(mmapFileName)

As the above example shows, it is acceptable to re-define a field with the same
type in the derived class. (Practically the re-definition is ignored.)

The re-definition is also acceptable if it defines the type of the field to 
be a base-type of the type of the field in the base class. This 
re-definition is also ignored::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         class BaseField(self.schema.Structure):
      ...             foo = self.schema.ByteString
      ...         class DerivedField(BaseField):
      ...             bar = self.schema.Int
      ...         class Base(self.schema.Structure):
      ...             field = DerivedField
      ...         class Root(Base):
      ...             field = BaseField
      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)
      >>> p.root.field = p.schema.BaseField()
      Traceback (most recent call last):
         ...
      TypeError: Expected <persistent class 'DerivedField'>, found <persistent class 'BaseField'>
      >>> p.close()
      >>> os.unlink(mmapFileName)

Finally, the re-definition is accepted even if it defines
the type of the field to be a type derived from the type of the field in the 
base class. This is the only case when the re-definition actually takes 
effect::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         class BaseField(self.schema.Structure):
      ...             foo = self.schema.ByteString
      ...         class DerivedField(BaseField):
      ...             bar = self.schema.Int
      ...         class Base(self.schema.Structure):
      ...             field = BaseField
      ...         class Root(Base):
      ...             field = DerivedField

      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)
      >>> p.root.field = p.schema.DerivedField()
      >>> p.root.field.foo = b"foo"
      >>> p.root.field.bar = 5
      >>> p.close()
      >>> os.unlink(mmapFileName)

It is not acceptable to re-define the type of the field to a completly 
unrelated one::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         class Base(self.schema.Structure):
      ...             name = self.schema.ByteString
      ...             age = self.schema.Int
      ...         class Root(Base):
      ...             name = self.schema.ByteString
      ...             weight = self.schema.Float
      ...             age = self.schema.Float

      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)
      Traceback (most recent call last):
         ...
      TypeError: Cannot re-define field 'age' defined in <persistent class 'Base'> as <persistent class 'Int'> to be of type <persistent class 'Float'>!
      >>> os.unlink(mmapFileName)
 
      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         class Base(self.schema.Structure):
      ...             name = self.schema.ByteString
      ...             age = self.schema.Int
      ...         class Root(Base):
      ...             name = self.schema.ByteString
      ...             weight = self.schema.Float
      ...             age = self.schema.Float

      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)
      Traceback (most recent call last):
         ...
      TypeError: Cannot re-define field 'age' defined in <persistent class 'Base'> as <persistent class 'Int'> to be of type <persistent class 'Float'>!
      >>> os.unlink(mmapFileName)

Persistent base classes must be defined in the same storage instance as the 
derived class.

The volatile base classes must be importable when the storage is opened::

      >>> class NonImportableVolatileBase(object):
      ...     pass

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         class Root(self.schema.Structure, NonImportableVolatileBase):
      ...             pass #name = self.schema.ByteString

      >>> p = MyStorage(mmapFileName, fileSize=1, stringRegistrySize=32)
      Traceback (most recent call last):
         ...
      TypeError: Cannot use the non-pickleable volatile class <class '__main__.NonImportableVolatileBase'> as a base class in the definition of the persistent structure <persistent class 'Root'>

That's it for getting started!
