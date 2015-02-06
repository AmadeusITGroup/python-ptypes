===============
Property Graphs
===============


The :mod:`~ptypes.graph` module provides extension classes for manipulating and
persistently storing property graphs.

We will play with a file called :file:`testfile.mmap`.
First we make sure there is no such file::

      >>> import os
      >>> mmapFileName = '/tmp/testfile.mmap'
      >>> try: os.unlink(mmapFileName)
      ... except: pass

Now we can start the actual work and create a new storage for a simple graph.
First we import the necessary classes::

      >>> from ptypes.storage import Storage
      >>> from ptypes.graph import Node, Edge

:class:`~ptypes.graph.Node` and :class:`~ptypes.graph.Edge` are *type
descriptor classes*: in order to be able to associate data to the nodes and
edges of a graph, they can be parametrized with other persistent types.
:class:`~ptypes.graph.Node` accepts a single type parameter and the defined
type will be able to store an instance of the specified type (or a reference to
such an instance, depending on wether that type is stored by value or
reference).

:class:`~ptypes.graph.Edge` represents directed edges in the graph.
It expects three type parameters:

* the type of the source (*from*) node
* the type of the target (*to*)node
* the type of the data associated with the edge itself

In the below snippet we create a persistent type called ``NodeOfString`` and
based on :class:`~ptypes.graph.Node` and one called ``EdgeOfString`` based on
:class:`~ptypes.graph.Edge`.
Instances of both can refer to an arbitrary ``String``.
Furthermore ``EdgeOfString`` can connect ``NodeOfString`` instances::

      >>> class MyStorage(Storage):
      ...     def populateSchema(self):
      ...         NodeOfString = self.define( Node('NodeOfString')[self.schema.String] )
      ...         self.define( Edge('EdgeOfString')[NodeOfString, NodeOfString, self.schema.String, ] )
      ...         class Root(self.schema.Structure):
      ...             node1 = self.schema.NodeOfString
      ...             node2 = self.schema.NodeOfString
      ...             node3 = self.schema.NodeOfString
      >>> p = MyStorage(mmapFileName, fileSize=16000, stringRegistrySize=32)
 
The ``Root`` object has three attributes capable of storing references to ``NodeOfString``
instances. Let's initialize them and connect them with edges like this::

      (node1) --> (node2) --> (node3)

      >>> p.root.node1 = p.schema.NodeOfString()
      >>> p.root.node2 = p.schema.NodeOfString()
      >>> p.root.node3 = p.schema.NodeOfString()
      >>> p.schema.EdgeOfString(p.root.node1, p.root.node2)          #doctest: +ELLIPSIS
      <persistent graph edge 'EdgeOfString' @offset 0x...L referring to None >
      >>> p.schema.EdgeOfString(p.root.node2, p.root.node3)            #doctest: +ELLIPSIS
      <persistent graph edge 'EdgeOfString' @offset 0x...L referring to None >

Tricky here: ``_`` refers to the result of the last statement, which prevents
closing the storage::

      >>> _                                        #doctest: +ELLIPSIS
      <persistent graph edge 'EdgeOfString' @offset 0x...L referring to None >

Unfortunately ``del _`` does not work::

      >>> del _                                          #doctest: +ELLIPSIS
      Traceback (most recent call last):
      ...
      NameError: name '_' is not defined

We need to type an expression that evaluates to other than ``None``,
so that it is assigned to ``_`` and we can close the storage::

      >>> "replace the edge in _"
      'replace the edge in _'
      >>> p.close()
      >>> os.unlink(mmapFileName)

Let's create a bit more elaborate graph from the example available at
https://github.com/tinkerpop/gremlin/blob/master/data/graph-example-1.json
The graph will have two types of nodes:

   * ``NDeveloper`` (associated with ``Developer`` instances, having ``id``, ``name`` and ``age`` attributes)
   * ``NSoftware`` (associated with ``Software`` instances, having ``id``, ``name`` and ``lang`` attributes)

The edges of the graph are going to be of the below types:

   * ``created``: points from ``NDeveloper`` to ``NSoftware``
   * ``knows``: points from ``NDeveloper`` to ``NDeveloper`` 

Both types of edges will be able to refer to a structure called ``WeightedRelation``,
which can express the extent to which a developer contributed to a software or
how well developers know each other.

To complicate things, we want to have an index of developers and pieces of
software sorted by name. We will use skip lists to implement these::

      >>> from ptypes.storage import Dict
      >>> from ptypes.pcollections import SkipList

      >>> sortOrder = """
      ... from operator import attrgetter
      ... getKeyFromValue=attrgetter('contents.name')"""

      >>> class MyStorage(Storage):
      ...
      ...     def populateSchema(self):
      ...
      ...         class Developer(self.schema.Structure):
      ...             id  = self.schema.Int
      ...             name = self.schema.String
      ...             age  = self.schema.Int
      ...
      ...         class Software(self.schema.Structure):
      ...             id  = self.schema.Int
      ...             name = self.schema.String
      ...             lang = self.schema.String
      ...
      ...         NDeveloper = self.define( Node('NDeveloper')[Developer] )
      ...         NSoftware  = self.define( Node('NSoftware')[Software] )
      ...
      ...         self.define( Dict('NDevelopersByName')[self.schema.String, self.schema.NDeveloper] )
      ...         self.define( SkipList('Developers')[self.schema.NDeveloper, sortOrder] )
      ...         self.define( SkipList('Programs')[self.schema.NSoftware, sortOrder] )
      ...
      ...         class WeightedRelation(self.schema.Structure):
      ...             id  = self.schema.Int
      ...             weight = self.schema.Float
      ...
      ...         self.define( Edge('created')[NDeveloper, NSoftware , WeightedRelation] )
      ...         self.define( Edge('knows'  )[NDeveloper, NDeveloper, WeightedRelation] )
      ...
      ...         class Root(self.schema.Structure):
      ...             devByName = self.schema.NDevelopersByName
      ...             dev = self.schema.Developers
      ...             sw = self.schema.Programs

      >>> p = MyStorage(mmapFileName, fileSize=16000, stringRegistrySize=32)

We can populate this data structure::

      >>> from json import loads
      >>> graphson = loads("""
      ... {
      ...   "vertices":[
      ...     {"name":"marko","age":29,"id":1},
      ...     {"name":"vadas","age":27,"id":2},
      ...     {"name":"lop","lang":"java","id":3},
      ...     {"name":"josh","age":32,"id":4},
      ...     {"name":"ripple","lang":"java","id":5},
      ...     {"name":"peter","age":35,"id":6}
      ...   ],
      ...   "edges":[
      ...     {"weight":0.5,"id":7,"_outV":1,"_inV":2,"_label":"knows"},
      ...     {"weight":1.0,"id":8,"_outV":1,"_inV":4,"_label":"knows"},
      ...     {"weight":0.4,"id":9,"_outV":1,"_inV":3,"_label":"created"},
      ...     {"weight":1.0,"id":10,"_outV":4,"_inV":5,"_label":"created"},
      ...     {"weight":0.4,"id":11,"_outV":4,"_inV":3,"_label":"created"},
      ...     {"weight":0.2,"id":12,"_outV":6,"_inV":3,"_label":"created"}
      ...   ]
      ... }""")
      >>> p.root.dev = p.schema.Developers()
      >>> p.root.sw = p.schema.Programs()
      >>> p.root.devByName = p.schema.NDevelopersByName(10)

      >>> allNodes = dict()
      >>> for properties in graphson["vertices"]:
      ...     nodes, NClass, Class = (p.root.sw, p.schema.NSoftware, p.schema.Software) if "lang" in properties else (p.root.dev, p.schema.NDeveloper, p.schema.Developer)
      ...     node = allNodes[properties["id"]] = NClass(Class(**properties))
      ...     nodes.insert(node)
      ...     if "lang" not in properties: p.root.devByName[properties["name"].encode()] = node

      >>> for properties in graphson["edges"]:                              #doctest: +ELLIPSIS
      ...     EdgeClass = getattr(p.schema, properties["_label"])
      ...     e = EdgeClass(allNodes[properties["_outV"]], allNodes[properties["_inV"]], p.schema.WeightedRelation(**properties) )

... and run a simple query::

      >>> for ndeveloper in p.root.devByName.itervalues():
      ...     developer = ndeveloper.contents.name
      ...     for _edge in ndeveloper.outEdges(p.schema.created):
      ...          developersProgram = _edge.toNode.contents.name
      ...          print 'developer = {}, developersProgram = {}'.format(developer, developersProgram)
      ...
      developer = peter, developersProgram = lop
      developer = marko, developersProgram = lop
      developer = josh, developersProgram = lop
      developer = josh, developersProgram = ripple

.. _declarative-queries:

Declarative Queries
-------------------

In general, a query has a two-fold functionality:
 * select certain combinations of the objects in the storage
 * do something useful with the selected combinations

Note that in the above example the only "useful" part is the print statement.
The rest is a set of for cycles and object navigation code, which is slow and
looks a bit boilerplate. The developer writing this code is forced to focus on *how*
(by what procedure) to enumerate the tuples of interest instead of concentrating
on *what* needs to be enumerated.

So here is a more efficient (no Python loops) and declarative way of achieving
the same goal::

      >>> from ptypes.query import Query, Each
      >>> from ptypes.graph import FindEdge, NodeAttribute

      >>> class MyQuery(Query):
      ...     _ndeveloper = Each('devByName')
      ...     developer = NodeAttribute(_ndeveloper, "name")
      ...     developersProgram = FindEdge('created'  , fromNode=_ndeveloper).toNode.attribute("name")
      >>> query = MyQuery(p)

      >>> query()
      ==== Results ====
      developer = peter, developersProgram = lop
      developer = marko, developersProgram = lop
      developer = josh, developersProgram = lop
      developer = josh, developersProgram = ripple
      ---- End of results ----

As you see, here the query is represented by a subclass of
:class:`~ptypes.query.Query` (called ``MyQuery``).
In the body of the subclass the query is defined by a set of *binding rules*. These rules
select the combinations of the persistent objects have to be processed by the query.
The actual processing of the combinations happens in the
:meth:`~ptypes.query.Query.processOne()` generator method of the
:class:`~ptypes.query.Query` class, which is invoked for each of the selected
combinations.
The default implementation of :meth:`~ptypes.query.Query.processOne()` prints
the header seen in the example, prints every tuple sent into it and finally
prints the footer.
The method can be overriden in subclasses, but has to remain a generator.

Let's have a closer look at the process of selecting the combinations. The first thing to
note is that some rules refer to other rules. For example, the ``developer`` rule and the  
one created by the :class:`~ptypes.graph.FindEdge` incovation refer to the
``ndeveloper`` rule.
The :attr:`~ptyopes.graph.FindEdge.toNode` attribute of the rule created by
:class:`FindEdge(...) <ptypes.graph.FindEdge>` is a rule referring to the rule
created by :class:`FindEdge(...) <ptyes.graph.FindEdge>`, etc.
The bottom line is that these references represent depenency relationships
among the rules and thus determine a partial ordering that has to be respected
at the time the rules are evaluated. It is an error if such an order does not
exist because of reference cycles.

When the query is executed, a :class:`~ptypes.query.QueryContext` is created.
Each binding rule can select multiple values to be bound to a name in the query
context.
The evaluation of the query starts by requesting a value from the first rule
according to the order and binding it to the name of the rule. Then a value
from the next rule is acquired and bound to its name, then the third, etc.
Each rule may rely on the values in the context bound by previous rules to
compute the values it supplies.
If there are no more rules, then the context is "complete", so it is passed to
the callback method (by default :meth:`~ptypes.query.Query.processOne()`).
After the callback returns or when a rule cannot provide a value, we
"backtrack", i.e. bind a new value from the previous rule to the name of that
rule and try again.
