======================
Persistent Collections
======================

The :mod:`~.ptypes.pcollections` module is intended for persistent container
data types a la the similarly named module of the standard library.
Currently the only such data type in the module is
:class:`~ptypes.pcollections.SkipList`.
(There are also a :class:`~ptypes.pcollections.Dict` and a
:class:`~ptypes.pcollections.List` data types in the :mod:`~ptypes.storage`
module.)

We will play with a file called :file:`testfile.mmap`.
First we make sure there is no such file::

      >>> import os
      >>> mmapFileName = '/tmp/testfile.mmap'
      >>> try: os.unlink(mmapFileName)
      ... except: pass

SkipLists are probabilistic data structures. As this document is also used for test runs,
and tests are nice if their results are reproducable, we seed the random number
generator here.
(You do not do this in a real world scenario.)::

      >>> from random import seed
      >>> seed(13)

Now we can start the actual work and create a new storage with a few skip lists.::

      >>> from ptypes.storage import Storage
      >>> from ptypes.pcollections import SkipList
      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         self.define( SkipList('ListOfStrings')[self.schema.String] )
      ...         self.define( SkipList('ListOfFloats')[self.schema.Float] )
      ...         self.define( SkipList('ListOfInts')[self.schema.Int] )
      ...         class Root(self.schema.Structure):
      ...             sortedStrings= self.schema.ListOfStrings
      ...             sortedFloats= self.schema.ListOfFloats
      ...             sortedInts= self.schema.ListOfInts
      >>> p = MyStorage(mmapFileName, fileSize=16000, stringRegistrySize=32)

We have created a new storage with a schema defining some persistent skip lists.
Let's instantiate those lists!::

      >>> p.root.sortedStrings = p.schema.ListOfStrings()
      >>> p.root.sortedFloats = p.schema.ListOfFloats()
      >>> p.root.sortedInts = p.schema.ListOfInts()

Right now they are empty::

      >>> for x in p.root.sortedStrings: print x
      >>> for x in p.root.sortedFloats : print x
      >>> for x in p.root.sortedInts   : print x

So let's populate the lists::

      >>> from random import random
      >>> text = "Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet. Lorem ipsum dolor sit amet, consetetur sadipscing elitr, sed diam nonumy eirmod tempor invidunt ut labore et dolore magna aliquyam erat, sed diam voluptua. At vero eos et accusam et justo duo dolores et ea rebum. Stet clita kasd gubergren, no sea takimata sanctus est Lorem ipsum dolor sit amet."
      >>> for word in text.split():
      ...     p.root.sortedStrings.insert(word)
      ...     p.root.sortedInts.insert(len(word))
      ...     p.root.sortedFloats.insert(random())

We can examine what data we entered into them::

      >>> ' '.join( str(word) for word in p.root.sortedStrings)
      'At At Lorem Lorem Lorem Lorem Stet Stet accusam accusam aliquyam aliquyam amet, amet, amet. amet. clita clita consetetur consetetur diam diam diam diam dolor dolor dolor dolor dolore dolore dolores dolores duo duo ea ea eirmod eirmod elitr, elitr, eos eos erat, erat, est est et et et et et et et et gubergren, gubergren, invidunt invidunt ipsum ipsum ipsum ipsum justo justo kasd kasd labore labore magna magna no no nonumy nonumy rebum. rebum. sadipscing sadipscing sanctus sanctus sea sea sed sed sed sed sit sit sit sit takimata takimata tempor tempor ut ut vero vero voluptua. voluptua.'
      >>> [x.contents for x in p.root.sortedInts]
      [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 8, 8, 8, 8, 8, 8, 9, 9, 10, 10, 10, 10, 10, 10]

.. comment: FIXME link stuff

The ``range(from, to)`` method can be used to iterate over items of the list falling into a given range.
Specifying ``None`` as ``from`` or ``to`` is respectively interpreted as starting the
iteration at the head or finishing the iteration at the tail, regardless of values of the head and tail.

For examample, let's start at the head and iterate till 0.5::

      >>> [x.contents for x in p.root.sortedFloats.range(None, 0.5)]
      [0.014432392962091867, 0.038827493571539695, 0.043208541161602665, 0.06914392433423655, 0.07327577792391804, 0.11226017699105972, 0.11736005057379029, 0.13021302275975688, 0.13078096193971112, 0.1348537611989652, 0.13700750396727945, 0.1417455635817888, 0.14671032194011457, 0.14715991816841778, 0.15975671807789493, 0.1644834338680018, 0.17663374761721184, 0.1857241738737354, 0.19446895049174417, 0.20262663200059494, 0.20305829275692444, 0.21171568976023003, 0.21390753049174072, 0.22516293556211264, 0.22555741047358735, 0.2305586089654681, 0.23544699374851974, 0.23567832921908183, 0.2533117560380147, 0.256707976428696, 0.2590084917154736, 0.2758368539391567, 0.29465675376336253, 0.2953250720566104, 0.31376136582532577, 0.3413338898282574, 0.3593511401342244, 0.3642026252197428, 0.366439909719686, 0.37475624323154333, 0.38968876005844033, 0.395757368872072, 0.4134909043927144, 0.4295776461864138, 0.4298222708601105, 0.4315803283922126, 0.4395906018119786, 0.44339995485526273, 0.45945902363778857, 0.48678549303293817, 0.49085713587721047]

Now let's start at 0.5 and iterate to the end::

      >>> [x.contents for x in p.root.sortedFloats.range(0.5, None)]
      [0.5226933014113342, 0.5313147518470183, 0.5433155946072753, 0.5542263583182457, 0.556152990512616, 0.5641385986016807, 0.5808745525911077, 0.5912249836224895, 0.6035000029031871, 0.6054987779269864, 0.6084021478742864, 0.6172404962969068, 0.6390555147357233, 0.6435268044107577, 0.6512317704341258, 0.6768215650986809, 0.6840312745816469, 0.6840819180161107, 0.6852579929645369, 0.6909226510552873, 0.7165110905234495, 0.7188819901966701, 0.7227143160726478, 0.727693576886414, 0.734023602212773, 0.7447501528022076, 0.7484114914175455, 0.7550038512774011, 0.793770550765207, 0.7982586371435578, 0.8031721215739205, 0.8060468380335744, 0.8060952775041057, 0.8097396112110605, 0.8196436434587475, 0.8263653401364824, 0.8376565105032981, 0.8381453785681514, 0.8493361613899302, 0.8499390127809929, 0.8536542179472612, 0.8682415206080506, 0.8712847291984398, 0.8861924242970314, 0.9329778169654616, 0.9493234167956348, 0.9536660422656937, 0.9713032894127117, 0.9856811855948702]
      >>> del x
      >>> p.close()

If we reopen the storage, we still have the same data in it::

      >>> p = Storage(mmapFileName, fileSize=1, stringRegistrySize=32)
      >>> ' '.join( str(word) for word in p.root.sortedStrings)
      'At At Lorem Lorem Lorem Lorem Stet Stet accusam accusam aliquyam aliquyam amet, amet, amet. amet. clita clita consetetur consetetur diam diam diam diam dolor dolor dolor dolor dolore dolore dolores dolores duo duo ea ea eirmod eirmod elitr, elitr, eos eos erat, erat, est est et et et et et et et et gubergren, gubergren, invidunt invidunt ipsum ipsum ipsum ipsum justo justo kasd kasd labore labore magna magna no no nonumy nonumy rebum. rebum. sadipscing sadipscing sanctus sanctus sea sea sed sed sed sed sit sit sit sit takimata takimata tempor tempor ut ut vero vero voluptua. voluptua.'

It is possible to retrieve individual values from the list::

      >>> p.root.sortedStrings["Lorem"]                                       #doctest: +ELLIPSIS
      <persistent String object 'Lorem' @offset 0x...L>
      >>> p.root.sortedStrings["Balmoral"]                                       #doctest: +ELLIPSIS
      Traceback (most recent call last):
      ...
      KeyError: 'Balmoral'
      >>> "Make _ refer to something else"
      'Make _ refer to something else'
      >>> p.close()
      >>> os.unlink(mmapFileName)

So far we have only inserted basic persistent types into the lists, for which
the :mod:`~ptypes.storage` module defines 3-way relational
operators, i.e. allows interpreting all of the *less than*, *greater than* and
*equals* relationships. This is not the case for structures: they can only
be compared for equility.

Let's see what happens if we try to insert structures into a skip list::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         class Agent(self.schema.Structure):
      ...             name = self.schema.String
      ...             age = self.schema.Int
      ...             weight = self.schema.Float
      ...
      ...         self.define( SkipList('ListOfAgents')[self.schema.Agent] )
      ...         class Root(self.schema.Structure):
      ...             sortedAgents= self.schema.ListOfAgents
      >>> p = MyStorage(mmapFileName, fileSize=16000, stringRegistrySize=32)
      >>> p.root.sortedAgents = p.schema.ListOfAgents()
      >>> for agentName, age, weight in (("Felix Leiter", 31, 95.3), ("Miss Moneypenny", 23, 65.4), ("Bill Tanner",57, 73.9)): #doctest: +ELLIPSIS
      ...     agent = p.schema.Agent(name=agentName, age=age, weight=weight )
      ...     p.root.sortedAgents.insert(agent)
      Traceback (most recent call last):
      ...
      TypeError: <persistent class 'Agent'> does not define a sort order!
      >>> del agent
      >>> p.close()
      >>> os.unlink(mmapFileName)

The pythonic way to overcome this is to define a comparison function or
(preferably) a function that extracts from the structure a key having a sort
order. The definitions of these functions have to be supplied in a string
containing a Python code snippet. The snippet will be executed in a name space
when the storage is opened and the persistent type is created.
If the name space contains the names ``getKeyFromValue`` or ``compare`` after
the execution of the snippet, then the objects associated with these names
will be called to get the keys from the values or to
perform 3-way comparison of the values inserted into the skip list.
The snippet becomes part of the type definition of the list and gets saved into the storage.::

      >>> sortOrder = """
      ... # Demonstrate when this snippet is executed (ommit this in real world scenarios)
      ... print "Sort order is now being defined."
      ...
      ... # This is the essential part. You have to define 'getKeyFromValue' and/or 'compare':
      ... from operator import attrgetter
      ... getKeyFromValue=attrgetter('age')
      ...
      ... def compare(x, y):
      ...     # demonstrate when we compare stuff by printing x & y
      ...     rv = cmp(x, y)
      ...     print "Comparing {0} and {1}: {2}".format(repr(x), repr(y), rv)
      ...     return rv
      ... """
      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         class Agent(self.schema.Structure):
      ...             name = self.schema.String
      ...             age = self.schema.Int
      ...             weight = self.schema.Float
      ...
      ...         self.define( SkipList('ListOfAgents')[self.schema.Agent, sortOrder] )
      ...         class Root(self.schema.Structure):
      ...             sortedAgents= self.schema.ListOfAgents
      >>> p = MyStorage(mmapFileName, fileSize=16000, stringRegistrySize=32)
      Sort order is now being defined.
      >>> p.root.sortedAgents = p.schema.ListOfAgents()
      >>> for agentName, age, weight in (("Felix Leiter", 31, 95.3), ("Miss Moneypenny", 23, 65.4), ("Bill Tanner",57, 73.9)): #doctest: +ELLIPSIS
      ...     agent = p.schema.Agent(name=agentName, age=age, weight=weight )
      ...     p.root.sortedAgents.insert(agent)
      Comparing ...
      >>> for agent in p.root.sortedAgents:
      ...     print agent.name
      Miss Moneypenny
      Felix Leiter
      Bill Tanner
      >>> del agent
      >>> p.close()

The next time we open the storage, the snippet is again executed::

      >>> p = Storage(mmapFileName, fileSize=16000, stringRegistrySize=32)
      Sort order is now being defined.
      >>> agent = p.schema.Agent(name="Auric Goldfinger", age=65, weight=87.3 )
      >>> p.root.sortedAgents.insert(agent)                                       #doctest: +ELLIPSIS
      Comparing ...
      >>> for agent in p.root.sortedAgents:
      ...     print agent.name
      Miss Moneypenny
      Felix Leiter
      Bill Tanner
      Auric Goldfinger
